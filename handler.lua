local cache = require "kong.tools.database_cache"
local responses = require "kong.tools.responses"

local singletons = require "kong.singletons"
local BasePlugin = require "kong.plugins.base_plugin"
local apiutil = require "kong.plugins.key-auth.apiutil"
local tokenutil = require "kong.plugins.key-auth.tokenutil"
local ownerutil = require "kong.plugins.key-auth.ownerutil"
local utils = require "kong.tools.utils"


local cjson = require "cjson.safe"


local ngx_set_header = ngx.req.set_header
local ngx_get_headers = ngx.req.get_headers
local set_uri_args = ngx.req.set_uri_args
local get_uri_args = ngx.req.get_uri_args
local clear_header = ngx.req.clear_header



local params = {}
local KeyAuthHandler = BasePlugin:extend()

KeyAuthHandler.PRIORITY = 1000

function KeyAuthHandler:new()
  KeyAuthHandler.super.new(self, "key-auth")
end



local function load_credential(keyid)

  local creds, err = singletons.dao.keyauth_token:find_all {
    id = keyid
  }

  if not creds then
    return nil, err
  end

  return creds[1].scopes
end






local function unserialize(str)  
  local EMPTY_TABLE = {} 
    if str == nil or str == "nil" then  
        return nil  
    elseif type(str) ~= "string" then  
        EMPTY_TABLE = {}  
        return EMPTY_TABLE  
    elseif #str == 0 then  
        EMPTY_TABLE = {}  
        return EMPTY_TABLE  
    end  
  
    local code, ret = pcall(loadstring(string.format("do local _=%s return _ end", str)))  
  
    if code then  
        return ret  
    else  
        EMPTY_TABLE = {}  
        return EMPTY_TABLE  
    end  
end  



local function to_utf8(a)  
  local n, r, u = tonumber(a)  
  if n<0x80 then                        -- 1 byte  
    return char(n)  
  elseif n<0x800 then                   -- 2 byte  
    u, n = tail(n, 1)  
    return char(n+0xc0) .. u  
  elseif n<0x10000 then                 -- 3 byte  
    u, n = tail(n, 2)  
    return char(n+0xe0) .. u  
  elseif n<0x200000 then                -- 4 byte  
    u, n = tail(n, 3)  
    return char(n+0xf0) .. u  
  elseif n<0x4000000 then               -- 5 byte  
    u, n = tail(n, 4)  
    return char(n+0xf8) .. u  
  else                                  -- 6 byte  
    u, n = tail(n, 5)  
    return char(n+0xfc) .. u  
  end  
end 



function checkpropToken(method,oriUri)
  local temp_params
  if method=="GET" then

      temp_params=apiutil.get_uri_params("/core/tokens/:ownerid",oriUri)
      --登录成功后生成token以后，记录用户状态为已登录
      if temp_params then
        params=utils.table_merge(temp_params,params)
        ownerutil.owner_login(params["ownerid"])
        generateSelfToken()
      end 


      temp_params=apiutil.get_uri_params("/uploads/tokens/:ownerid",oriUri)

      --判断url的ownerid与token中的ownerid是否一致
      if temp_params then 
        params=utils.table_merge(temp_params,params)
        local token = params["token"]
        if token then
          local oriToken = tokenutil.get_tokenAgent(token)
          local access_ownerid = oriToken["u"]
          if access_ownerid~=params["ownerid"] then
            return responses.send_HTTP_OK("wrong ownerid")
          else
            --upatetoken之前先删除上一个token
            tokenutil.delete_token(oriToken["a"])
          end
        end
         generateSelfToken()
      end 

      

    elseif method=="DELETE" then
      temp_params=apiutil.get_uri_params("/core/tokens/:ownerid/:tokenid",oriUri)
      --如果用户退出登录 则删除最后一次的token 以及改变用户登录状态为未登录
      if temp_params then
        params=utils.table_merge(temp_params,params)
        tokenutil.delete_token(params)
        ownerutil.owner_logout(params["ownerid"])
        return responses.send_HTTP_OK("删除成功")
      end 
    end
end


function generateSelfToken()
   local scopes_public= singletons.dao.keyauth_scope:find_all{public=true}
      local scopes = singletons.dao.keyauth_scope:find_all{public = false}


      local scopeStr = apiutil.generateScope(scopes_public,scopes)
      local ownerid = params['ownerid']
      local tokenParams = {["selfuse"]=true,["ownerid"]=ownerid,["scopes"]=scopeStr,["note"]=ownerid,["usage"]="sk"}

      local tokenRes=tokenutil.issue_token(tokenParams)

      return responses.send_HTTP_OK(apiutil.generateToken("sk",ownerid,tokenRes["id"]))
    end 


function checkRedirect(oriUri,pattern)
    local from, _, err = ngx.re.find(oriUri,pattern, "oj")
    if from then
        ngx.req.set_uri(ngx.ctx.uri)
    end 
end

 

function KeyAuthHandler:access(conf)
  KeyAuthHandler.super.access(self)


  --所有参数
  params = apiutil.retrieve_parameters()
  local method= ngx.req.get_method()
  local oriUri=apiutil.split(ngx.req.raw_header()," ")[2]


  --处理登录注册和查询所有scope,此时不需要token和ownerid，直接转发
  checkRedirect(oriUri,[[\/login]])
  checkRedirect(oriUri,[[\/scopes]])


  --登陆后第一次生成用户token和token定时刷新，以及退出时删除token
  checkpropToken(method,oriUri)


  --token增删改查
  local from, _, err = ngx.re.find(ngx.var.uri, [[\/api\/token]], "oj")

  local token = params["token"]

  local tokenObj = {}

    --除了登录注册和查询所有scopes 其他的uri必须带token参数
    if not token then
      --如果无token参数则报错
        return responses.send_HTTP_INTERNAL_SERVER_ERROR("参数有误缺少token")
    else
      --如果有token参数，先判断token的格式是否正确
      local tokenObj=tokenutil.get_tokenAgent(token)
      ngx.log(ngx.ERR,"++++"..cjson.encode(tokenObj))
      params["ownerid"]=tokenObj["u"]
      params["tokenid"]=tokenObj["a"]
      if not params["ownerid"] then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR("token有误缺少ownerid信息")
      end

      if not params["tokenid"] then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR("token有误缺少tokenid信息")
      end

      --则根据token的id对应的scopes数据判断是否有此接口的权限，
      --如果此token的权限包含此接口的权限，则把token中的用户id连接到url后再转发
      --（upstream服务器端判断如果有此用户id则使用此用户id，无此用户id则使用session中的用户id，都没有则报错）
    
      local scopes=load_credential(params["tokenid"])
      local myscopes=apiutil.getScope(oriUri,method)

      local flag = false

      for i = 1, #myscopes do

          local index = string.find(scopes,myscopes[i], 1)

          if not index then
            break
          elseif i==#myscopes then
            flag=true
          end
       end
       
       if flag then
        --如果token的格式正确，url为token的增删改查，则在本地处理数据库
        if from then
          if method=="POST" then
            tokenutil.issue_token(params)
          elseif method=="GET" then
            tokenutil.get_token(params)
          elseif method== "PATCH" then

          elseif method=="DELETE" then
            tokenutil.delete_token(params)
          end
       --如果token的格式正确，url为其他接口，
       else 
          ngx.req.set_uri(ngx.ctx.uri.."/"..params["ownerid"])
       end
      end
 
   end
   return responses.send_HTTP_OK("nothing")
end

return KeyAuthHandler