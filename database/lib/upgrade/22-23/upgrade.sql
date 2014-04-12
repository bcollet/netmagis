------------------------------------------------------------------------------
-- Database upgrade to 2.3 version
--
-- Use:
--	psql --no-psqlrc --single-transaction -f upgrade.sql database-name
--
-- Please, make a backup of your existing database first!
-- Use a tool such as nohup or script in order to log output and check
-- error messages:
--	- Lines with "NOTICE:" are not important.
--	- You should pay attention to lines with "ERROR:" 
------------------------------------------------------------------------------

CREATE TABLE global.session (
    token	TEXT NOT NULL,		-- auth token in session cookie
    idcor	INT,			-- user authenticated by this token
    lastlogin	TIMESTAMP (0) WITHOUT TIME ZONE
                        DEFAULT CURRENT_TIMESTAMP
			NOT NULL,	-- last successful login
    lastaccess	TIMESTAMP (0) WITHOUT TIME ZONE
                        DEFAULT CURRENT_TIMESTAMP
			NOT NULL,	-- last access to a page

    FOREIGN KEY (idcor) REFERENCES global.nmuser (idcor),
    PRIMARY KEY (token)
) ;

INSERT INTO global.config (key, value) VALUES ('authexpire', '600') ;

UPDATE global.config SET value = '23' WHERE key = 'schemaversion' ;
