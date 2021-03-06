

local utils = require "kong.tools.utils"
local constants=require "kong.plugins.key-auth.constants"
local apiutil = require "kong.plugins.key-auth.apiutil"
local singletons = require "kong.singletons"
local responses = require "kong.tools.responses"
local crypto = require "crypto"
local cjson = require "cjson.safe"
local role_privlleges = "kong.plugins.key-auth.role"



local _M = {}

--记住用户登录状态
_M.owner_login=function(eid)
  local ent, err = singletons.dao.keyauth_ent:find_all {ownerid = eid}
  local update_ent 
  if (#ent)>0 then
      local tempent=ent[1]
      update_ent, err = singletons.dao.keyauth_ent:update({status="1"},{id=tempent["id"],ownerid=eid,paytype=tempent["paytype"]})
    else 
      update_ent, err =singletons.dao.keyauth_ent:insert {id = utils.uuid(),ownerid=eid,status="1"}
  end
  if err then
    return responses.send(401,err)
  end

end




  _M.getUserPayInfo=function ( ownerid )
    if ownerid then
      local  owners,err = singletons.dao.ent:find_all{id=ownerid}
      local  owner = owners[1]
      if owner and (not owner.type) then
        return "primary"
      else 
        return owner["paytype"]
      end
         

    end

    
  end




_M.owner_logout=function (ownerid)
  local ent, err = singletons.dao.keyauth_ent:find_all {ownerid = ownerid}
  local update_ent, err 
  if ent then
      update_ent, err = singletons.dao.keyauth_ent:update {id = ent.id,ownerid=ent.ownerid,status="0",paytype=ent.paytype}
  else
      return responses.send_HTTP_OK("无此用户或者用户未登录")
  end
  if err then
    return responses.send(401,"更新用户状态失败")
  end
end


return _M
