CREATE DATABASE lab_8_1 CONTAINMENT = PARTIAL;
ALTER DATABASE lab_8_1 SET COMPATIBILITY_LEVEL = 110;
USE lab_8_1;

CREATE TABLE Employee
	(
		employee_id INT NOT NULL IDENTITY(1,1) PRIMARY KEY,
		salary MONEY NOT NULL,
		name NVARCHAR(50) NOT NULL,
		phone NVARCHAR(50) NOT NULL
	);

INSERT INTO Employee (name, phone, salary)
		VALUES ('FIO1', 'phone1', 25000), ('FIO2', 'phone2', 26000),
			('FIO3', 'phone3', 27000), ('FIO4', 'phone4', 28000);

/* Разрешить использование автономных баз данных на уровне сервера.
	Автономные базы данных хранят всю необходимую для работы и настройки информацию в себе. 
	Такие базы полностью независимы от настроек SQL сервера, не имеют внешних зависимостей и содержат в себе все механизмы аутентификации. 
	Так же не имеет значения, какая настройка языка выставлена у сервера.
*/

/* Enabled Advanced options. Разрешить работать с настройками с закладки Advanced. */
sp_configure 'show advanced', 1; RECONFIGURE WITH OVERRIDE; 
/* Enabled Database Containment. Разрешить использование автономных баз данных. */
sp_configure 'contained database authentication', 1; RECONFIGURE WITH OVERRIDE;

--CREATE USER EAdmin WITHOUT LOGIN;
CREATE USER EAdmin WITH PASSWORD='1', DEFAULT_SCHEMA=[dbo];
GRANT CONTROL ON DATABASE::lab_8_1 TO EAdmin;
ALTER ROLE db_owner ADD MEMBER EAdmin;
ALTER ROLE db_securityadmin ADD MEMBER EAdmin;

USE master;
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'strong';
BACKUP MASTER KEY TO FILE = 'C:\Users\win22\Desktop\backups\BMK.key' ENCRYPTION BY PASSWORD = 'strong';

CREATE CERTIFICATE ECert WITH SUBJECT = 'Certificate';
BACKUP CERTIFICATE ECert TO FILE = 'C:\Users\win22\Desktop\backups\ECert.crt' 
	WITH PRIVATE KEY (FILE = 'C:\Users\win22\Desktop\backups\ECert.key', ENCRYPTION BY PASSWORD = 'strong');

USE lab_8_1;
CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_128
	ENCRYPTION BY SERVER CERTIFICATE ECert;

ALTER DATABASE lab_8_1 SET ENCRYPTION ON;

SELECT name, is_encrypted FROM sys.databases;

BACKUP DATABASE lab_8_1 TO DISK = 'C:\Users\win22\Desktop\backups\lab_8_1.bak'
	WITH INIT, NAME = 'lab_8_1', MEDIANAME = 'lab_8_1', DESCRIPTION = 'lab_8_1';



CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'VeryStrong';

CREATE CERTIFICATE ECert
  FROM FILE = N'H:\SQLDEVELOPER\MSSQL15.MSSQLSERVER\MSSQL\Backup\ECert.crt'
  WITH PRIVATE KEY ( 
    FILE = N'H:\SQLDEVELOPER\MSSQL15.MSSQLSERVER\MSSQL\Backup\ECert.key',
 DECRYPTION BY PASSWORD = 'strong'
  );

RESTORE HEADERONLY FROM DISK = 'H:\SQLDEVELOPER\MSSQL15.MSSQLSERVER\MSSQL\Backup\lab_8_1.bak';
RESTORE FILELISTONLY FROM DISK = 'H:\SQLDEVELOPER\MSSQL15.MSSQLSERVER\MSSQL\Backup\lab_8_1.bak'

RESTORE DATABASE lab_8_1 FROM DISK = 'H:\SQLDEVELOPER\MSSQL15.MSSQLSERVER\MSSQL\Backup\lab_8_1.bak' WITH FILE = 1,
	MOVE N'lab_8_1' TO N'H:\SQLDEVELOPER\MSSQL15.MSSQLSERVER\MSSQL\DATA\lab_8_1.mdf',
	MOVE N'lab_8_1_log' TO N'H:\SQLDEVELOPER\MSSQL15.MSSQLSERVER\MSSQL\DATA\lab_8_1_log.ldf';

SELECT name, is_encrypted FROM sys.databases;

SELECT * FROM lab_8_1.dbo.Employee; 

