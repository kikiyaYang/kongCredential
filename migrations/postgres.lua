return {
  {
    name = "2017-05-06-172400_init_keyauth",
    up = [[
      CREATE TABLE IF NOT EXISTS keyauth_token(
        id uuid,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        modified_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        expired_at timestamp without time zone default (CURRENT_TIMESTAMP(6) at time zone 'utc'),
        note text,
        ownerid text,
        usage text,
        token text,
        scopes text,
        isdeleted bool,
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('keyauth_token_id')) IS NULL THEN
          CREATE INDEX keyauth_token_id ON keyauth_token(id);
        END IF;
        IF (SELECT to_regclass('keyauth_token_ownerid')) IS NULL THEN
          CREATE INDEX keyauth_token_ownerid ON keyauth_token(ownerid);
        END IF;
      END$$;



      CREATE TABLE IF NOT EXISTS keyauth_scope(
        id text,
        name text,
        description text,
        public bool,
        PRIMARY KEY (id)
      );


      DO $$
      BEGIN
        IF (SELECT to_regclass('keyauth_scope_id')) IS NULL THEN
          CREATE INDEX keyauth_scope_id ON keyauth_scope(id);
        END IF;
        IF (SELECT to_regclass('keyauth_scope_name')) IS NULL THEN
          CREATE INDEX keyauth_scope_name ON keyauth_scope(name);
        END IF;
      END$$;



      CREATE TABLE IF NOT EXISTS keyauth_ent(
        id text,
        status text,
        ownerid text,
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('keyauth_ent_id')) IS NULL THEN
          CREATE INDEX keyauth_ent_id ON keyauth_ent(id);
        END IF;
      END$$;

    ]],
    down = [[
      DROP TABLE keyauth_token;
      DROP TABLE keyauth_scope;
      DROP TABLE keyauth_ent;

    ]]

  }
}