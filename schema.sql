
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS feeds (
       handle	VARCHAR(30) PRIMARY KEY NOT NULL,	
       url 	TEXT UNIQUE NOT NULL);
CREATE TABLE IF NOT EXISTS gets (
          url    TEXT UNIQUE NOT NULL,
          etag   TEXT,
          time   TEXT,
          FOREIGN KEY(url) REFERENCES feeds(url) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS assoc (
       id       INTEGER PRIMARY KEY,
       jid   	VARCHAR(150) NOT NULL,
       handle 	VARCHAR(30)  NOT NULL,
       CONSTRAINT jidhandle UNIQUE (jid, handle),
       FOREIGN KEY(handle) REFERENCES feeds(handle) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS feeditems (
       id    	INTEGER PRIMARY KEY,
       date 	INTEGER,
       handle   VARCHAR(30) NOT NULL,
       title    VARCHAR(255),
       url	TEXT UNIQUE NOT NULL,
       body 	TEXT NOT NULL,
       send     INTEGER,	
       FOREIGN KEY(handle) REFERENCES feeds(handle) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS queue (
       id    	INTEGER PRIMARY KEY,
       handle 	VARCHAR(30) NOT NULL,
       jid	VARCHAR(150) NOT NULL,
       body 	TEXT NOT NULL,
       FOREIGN KEY(handle) REFERENCES feeds(handle));

