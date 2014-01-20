CREATE TABLE leafyd_index (indexid integer primary key autoincrement, uid text, seqno text, queue text, file text, timestamp integer, port_assigned int);
CREATE TABLE server_port (server_portid integer primary key autoincrement, port integer, host text, timestamp integer);
CREATE INDEX port on server_port (port);
CREATE INDEX queue on leafyd_index (queue);
CREATE INDEX seqno on leafyd_index (seqno);
CREATE INDEX server_port_timestamp on server_port (timestamp);
CREATE INDEX timestamp on leafyd_index (timestamp);
CREATE INDEX uid on leafyd_index (uid);
