CREATE TABLE _MetaData
        (
            _FormatVersion INTEGER,
            _ProductVersion TEXT,
            _BuildVersion TEXT,
            _SchemaHash TEXT
        );
CREATE TABLE Unit
            (
                UnitID BLOB PRIMARY KEY NOT NULL,
                ContainerID BLOB,
                ContainmentName TEXT,
                TreeConflict LONG,
                ContentsHash TEXT,
                ContentsConflicts TEXT
            );
CREATE TABLE _Transaction (LastTransactionID TEXT);
