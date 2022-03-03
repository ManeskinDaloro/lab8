-- 1. Создание пользователя и инициализация
BEGIN
	DROP LOGIN EAdmin;
	CREATE LOGIN EAdmin WITH PASSWORD=N'SqlServer123';

	
	CREATE DATABASE lab_8_1;
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

	CREATE DATABASE lab_8_2;
	USE lab_8_2;

	CREATE TABLE Company
	(
		company_id INT NOT NULL IDENTITY(1,1) PRIMARY KEY,
		age INT NOT NULL,
		name NVARCHAR(50) NOT NULL
	);

	USE master;
	USE lab_8_1;
	USE lab_8_2;

	CREATE USER EAdmin FROM LOGIN EAdmin;
	ALTER ROLE db_ddladmin ADD MEMBER EAdmin;
	GRANT CONTROL TO EAdmin;

END;

--2. Прозрачное шифрование и дешифрование данных

--#region
-- 2.1

/* TDE doesn't increase the size of the encrypted database. Encryption of a database file is done at the page level. 
	The pages in an encrypted database are encrypted before they're written to disk 
	and are decrypted when read into memory. TDE doesn't increase the size of the encrypted database.

	Прозрачное шифрование данных используется для шифрования и расшифровывания данных и файлов журналов,
	соответственно, шифруя данные перед их записью на диск и расшифровывает данные перед их возвратом в приложение. 
	Данный процесс выполняется на уровне SQL, полностью прозрачен для приложений и пользователей.
	
	Но если злоумышленник украдет физический носитель, например диски или ленты резервного копирования, 
	то он сможет восстановить или подключить базу данных и просмотреть ее данные. Одним из решений может стать шифрование конфиденциальных данных в базе данных
	и использование сертификата для защиты ключей шифрования данных. Таким образом, пользователи без ключей не смогут использовать эти данные. 
	Но этот тип защиты необходимо запланировать заранее.
	
	Это позволяет разработчикам программного обеспечения шифровать данные с помощью алгоритмов шифрования AES и 3DES, не меняя существующие приложения.

	Функция прозрачного шифрования данных не обеспечивает шифрование каналов связи. Дополнительные сведения о способах шифрования данных, передаваемых по каналам связи. */

ALTER DATABASE lab_8_1 SET OFFLINE;
ALTER DATABASE lab_8_1 SET ONLINE;

USE master;

EXECUTE AS USER = 'EAdmin'; -- Выбрать бд для которой будет выполнено EXECUTE AS
REVERT; -- Откатиться на предыдущего пользователя в бд, где было использовано EXECUTE AS
SELECT SUSER_NAME(), USER_NAME();

-- CREATE AND BACKUP DATABASE MASTER KEY, CERT: выполнять все в master, это вещи на уровне сервера
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'strong';
GO
BACKUP MASTER KEY TO FILE = 'H:\SQLDEVELOPER\MSSQL15.MSSQLSERVER\MSSQL\Backup\DMK.key' 
	ENCRYPTION BY PASSWORD = 'strong';

CREATE CERTIFICATE ECert WITH SUBJECT = 'DEK Certificate';
GO
BACKUP CERTIFICATE ECert TO FILE = 'H:\SQLDEVELOPER\MSSQL15.MSSQLSERVER\MSSQL\Backup\ECert.crt' 
	WITH PRIVATE KEY (FILE = 'H:\SQLDEVELOPER\MSSQL15.MSSQLSERVER\MSSQL\Backup\ECert.key', 
	ENCRYPTION BY PASSWORD = 'strong');

USE lab_8_1;

CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_128
	ENCRYPTION BY SERVER CERTIFICATE ECert;
GO
ALTER DATABASE lab_8_1 SET ENCRYPTION ON; -- Для это нужен DEK

SELECT name, is_encrypted FROM sys.databases; -- Посмотреть для каких бд включено TDE.

BACKUP DATABASE lab_8_1 TO DISK = 'H:\SQLDEVELOPER\MSSQL15.MSSQLSERVER\MSSQL\Backup\lab_8_1.bak'
	WITH INIT, NAME = 'lab_8_1', MEDIANAME = 'lab_8_1', DESCRIPTION = 'lab_8_1';
--#endregion

-- Шифрование столбца

--#region
-- У нас у же есть DMK and CERTIFICATE, создавали для TDE.
-- Создали симметричный ключ, подписанный сертификатом.
USE master;

CREATE SYMMETRIC KEY SSN_Key_01 
	WITH ALGORITHM = AES_128 
	ENCRYPTION BY CERTIFICATE ECert;  

-- Расшифровываем для зашифровки столбца, до этого он был зашифрован сертификатом, иерархия
OPEN SYMMETRIC KEY SSN_Key_01  
   DECRYPTION BY CERTIFICATE ECert;

USE lab_8_2;

TRUNCATE TABLE dbo.Company;
ALTER TABLE dbo.Company ADD NationalIDNumber NVARCHAR(30);
INSERT dbo.Company (name, age, NationalIDNumber) VALUES ('name1', 1, 'N12312');
ALTER TABLE dbo.Company ADD EncryptedNationalIDNumber VARBINARY(128); -- Шифрует в бинарном формате

USE master; -- Ключ находиться там => чтобы он отработал выбираем мастера

UPDATE lab_8_2.dbo.Company  
SET EncryptedNationalIDNumber = EncryptByKey(Key_GUID('SSN_Key_01'),
	convert(VARBINARY, NationalIDNumber));

SELECT * FROM lab_8_2.dbo.Company; 

SELECT NationalIDNumber, EncryptedNationalIDNumber AS 'Encrypted ID Number', 
	CONVERT(NVARCHAR, DecryptByKey(EncryptedNationalIDNumber)) AS 'Decrypted ID Number'  
FROM lab_8_2.dbo.Company;

CLOSE SYMMETRIC KEY SSN_Key_01;
--#endregion

-- Восстановление зашифрованной базы данных

--#region Restore Enctypted Database

-- Сначала зашифрованный бэкап, TDE шифрует процесс I/O pages,
-- Может понадобиться юзер с правами для всех этих вещей на другом сервере, а может надо без привзяки к логину ?
-- Может понадабятся права или что-то еще ?

CREATE LOGIN EAdmin WITH PASSWORD=N'SqlServer123';

-- Чтобы сделать имитацию восстановления на своем сервере
USE lab_8_1;
ALTER DATABASE lab_8_1 SET ENCRYPTION OFF;
DROP DATABASE ENCRYPTION KEY;

USE master;
DROP SYMMETRIC KEY SSN_Key_01 -- Для шифрования столбца;
GO
DROP CERTIFICATE ECert;
GO
DROP MASTER KEY;
GO

-- Основная часть
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'VeryStrong'; -- Для сертификата и других ключей, шифрует иерархию ниже: сертификаты, ассимитричные ключи

CREATE CERTIFICATE ECert
  FROM FILE = N'H:\SQLDEVELOPER\MSSQL15.MSSQLSERVER\MSSQL\Backup\ECert.crt'
  WITH PRIVATE KEY ( 
    FILE = N'H:\SQLDEVELOPER\MSSQL15.MSSQLSERVER\MSSQL\Backup\ECert.key',
 DECRYPTION BY PASSWORD = 'strong'
  );
GO

RESTORE HEADERONLY FROM DISK = 'H:\SQLDEVELOPER\MSSQL15.MSSQLSERVER\MSSQL\Backup\lab_8_1.bak';
RESTORE FILELISTONLY FROM DISK = 'H:\SQLDEVELOPER\MSSQL15.MSSQLSERVER\MSSQL\Backup\lab_8_1.bak';

RESTORE DATABASE lab_8_1 FROM DISK = 'H:\SQLDEVELOPER\MSSQL15.MSSQLSERVER\MSSQL\Backup\lab_8_1.bak' WITH FILE = 1,
	MOVE N'lab_8_1' TO N'H:\SQLDEVELOPER\MSSQL15.MSSQLSERVER\MSSQL\DATA\lab_8_1.mdf',
	MOVE N'lab_8_1_log' TO N'H:\SQLDEVELOPER\MSSQL15.MSSQLSERVER\MSSQL\DATA\lab_8_1_log.ldf';

SELECT name, is_encrypted FROM sys.databases;

-- Можно расшифровать БД дополнительно если надо, так как после бэкапа она остается шифрованной
USE lab_8_1;
ALTER DATABASE lab_8_1 SET ENCRYPTION OFF;
DROP DATABASE ENCRYPTION KEY;
--#endregion



-- EKM

--#region EKM (Extensible Key Managment)

/* Module (HSM - Hardware Security Modules) or EKM device to generate, manage, and
	store encryption keys for the network infrastructure outside of a SQL Server environment.
	SQL Server can make use of these keys for internal use. The HSM/EKM device can be a hardware appliance,
	a USB device, a smart card, or even software, as long as it 
	implements the Microsoft Cryptographic Application Programming Interface (MCAPI) provider. */

-- Создаем провайдера на azure (а нет, 200$) или подключаем криптографического провадера другой компании (third_party) 

-- Включаем EKM
EXEC sp_configure 'show advanced options', 1;
GO
RECONFIGURE;
GO
EXEC sp_configure 'EKM provider enabled', 1;
GO
RECONFIGURE;
GO

-- Подключаем провайдера в SQL SERVER
CREATE CRYPTOGRAPHIC PROVIDER AzureEKMProvider 
FROM FILE = N'C:\Program Files\SQL Server Connector for Microsoft Azure Key Vault\Microsoft.AzureKeyVaultService.EKM.dll';

CREATE CREDENTIAL AzureEKMCredential
    WITH IDENTITY = 'ADMIN\Admin',
    SECRET = 'AzureEKMKeySecret'
FOR CRYPTOGRAPHIC PROVIDER AzureEKMProvider;

ALTER LOGIN [ADMIN\Admin] 
ADD CREDENTIAL AzureEKMCredential;

CREATE ASYMMETRIC KEY AsymmKeyForEKM 
FROM PROVIDER AzureEKMProvider
WITH ALGORITHM = RSA_2048, 
PROVIDER_KEY_NAME = 'Lab8VaultKey_RSA_2048', 
CREATION_DISPOSITION = OPEN_EXISTING; -- Или создать новый CREATE_NEW

-- Защищаем наш симметричный ключ сильным провайдерским ключом
CREATE SYMMETRIC KEY SymKey_ProtectedByLab8VaultKeyKey 
WITH ALGORITHM = AES_256 
ENCRYPTION BY ASYMMETRIC KEY Lab8VaultKey_RSA2048_Key;

-- Шифрование данных на прямую
SELECT EncryptByAsymKey(AsymKey_ID('Lab8VaultKey_RSA_2048'),
	CONVERT(VARBINARY, phone))
FROM lab_8_1.dbo.Employee;

SELECT provider_id, name, guid, version, dll_path, is_enabled
FROM sys.cryptographic_providers;
--#endregion



-- Шифрование соединения
--#region

BEGIN
	sp_readerrorlog 0, 1, 'Cert';
	SELECT session_id, connect_time, net_transport, encrypt_option FROM sys.dm_exec_connections;
END


/* 
	Создаем свой сертификат со своей подписью через POWERSHELL:
		New-SelfSignedCertificate -CertStoreLocation H:\SQLDEVELOPER\MSSQL15.MSSQLSERVER\MSSQL\Cert -DnsName "mylocalsql.local" -FriendlyName "MyLocalSqlCert" -NotAfter (Get-Date).AddYears(1)

	(Configure network in SQL CONFIGURATION MANAGER):
		Force Enryption ON and choose certificate and restart service;
		In sql connection options select encrypt connection and trust server certificate. */
--#endregion



-- Постоянное шифрование - Always Encrypted (бдшная тема, столбцы).
--#region
/* To use Always Encrypted, you have to perform the
following three steps:
		1. Create a column master key (CMK).
		2. Create a column encryption key (CEK).
		3. Create a table with one or more encrypted columns. */

/* TDE doesn’t prevent database administrators and other users from having access to sensitive 
	information within the database. Always Encrypted — это функция, предназначенная для защиты конфиденциальных данных,
	таких как номера кредитных карт или номера документов, которые хранятся в базах данных: SQL Azure и SQL Server.
	Постоянное шифрование позволяет клиентам шифровать конфиденциальные данные в клиентских приложениях,
	не раскрывая ключи шифрования. Таким образом, постоянное шифрование позволяет разделить пользователей на тех, 
	кто владеет данными или имеет право их просматривать, и тех, кто управляет данными, но не должен иметь к ним доступа. 
	У локальных администраторов баз данных, операторов облачных баз данных и 
	других неавторизованных пользователей с высоким уровнем привилегий нет доступа к зашифрованным данным, 
	поэтому постоянное шифрование позволяет клиентам хранить конфиденциальные данные вне сферы их непосредственного контроля. 
	При этом организации могут хранить данные в Azure, делегировать права администратора локальной базы данных третьим лицам 
	или упростить требования к безопасности для собственных администраторов базы данных. */

USE lab_8_2;

-- Генерируем сертификат в Always Encypted Keys и создаем CMK, проверяем срок действия
-- Лучше генерировать все через обозреватель обьектов (в Always Encypted Keys), чтобы наверняка, чтобы срок действия и опции совпадали.
CREATE COLUMN MASTER KEY [CMK]
WITH
(
	KEY_STORE_PROVIDER_NAME = N'MSSQL_CERTIFICATE_STORE',
	KEY_PATH = N'CurrentUser/My/16ABA9821B9698CE53C6D9725CAA14C3EBDA266D'
);
CREATE COLUMN ENCRYPTION KEY CEK
WITH VALUES
(
	COLUMN_MASTER_KEY = CMK,
	ALGORITHM = 'RSA_OAEP',
	ENCRYPTED_VALUE = 0x01980000016D006900630072006F0073006F0066007400200073006F0066007400770061007200650020006B00650079002000730074006F0072006100670065002000700072006F00760069006400650072002F00310064003900330033003900370032002D0030003900300030002D0034003900660038002D0038006200320038002D00320066003900320062003100620035003900320039003400B55EF7341AB05ACE8A92CF2C05CF1942AEABB61368B32CE4F2A1D6F31D6E8A40B6D7FBAB92FF625F119E92AE627B1A70375D74EA38F6EA23BEEDC77C0A20C74A916652977D3C9F717CCB6568927229F35256C78C169B4CD3092F24BD62E474FE0E63A52D30A7A8F44A2A6BF390124E094757D815CEA4C5C47ACCAD2161A0B7D15E139FD9EA2AC3C2304209702FE6193358157C75ADC68E3EA4A2B31DED73E96C11627F2A1825511169D5B81111F30DA900B86DFE5A35D5D32CFD2B5C88CF5D04AAFFE055E239A539E727589BA250AF500E43EC14ADD0FF16CD8D97950D313EAECF952405D9C398F473C3F665B1AFBEB05A26C363549A72CC32EDF6FDD4BEF575281315D3C0823E1975DB72FBD0A16B39D827793122F05EFD8F40851618BA473A28770063F2B1BEC637F0D0D7976E45D228AFEF65E9FC01BA28A86B23D885AC77139550C54847321FDE84E04A2894DC18A92C2DA14AE475FCF9E1919BE154789C0732DFB9FB72270DA116F4BF481CBDBB698F3DCD66E8F1CEFC0A2AF71303B79DE47600CAD6F6E7D728AAAA00B80445A13F87ACDEDC5906D529CE124DC9BC935DBC2A18FEE86A0783E8A62CDC82847CE53EC079845615279D9587F5CAA453D4C09073DE55CC547CBE9B024C4A7855C15863202880B69740027B08A76A6E1DBCD9B143B97426617075462626FE05116601483594FADC439E5380C631C807681EE0
);

/* Special format must use with COLLATE Latin1_General_BIN2
	Deterministic encryption - алгоритм будет зашифровывать одну и ту же строку одинаково, 
	Randomized encryption - *каждый раз по новому
*/

DROP TABLE IF EXISTS Customers;
CREATE TABLE Customers (  
    SSN nvarchar(11) COLLATE Latin1_General_BIN2 ENCRYPTED WITH (COLUMN_ENCRYPTION_KEY = CEK,  
        ENCRYPTION_TYPE = DETERMINISTIC, ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256')
);

-- Можно зашифровать уже имеющие данные с помощью WIZARD, ПКМ по таблице => Encrypt Columns.
-- А для динамической зашифровки используются приложения, например с ADO.NET.

-- Можно включить опцию Always Encrypted в подключении к серверу, чтобы расшифровать данные
SELECT * FROM Customers;
--#endregion


-- Useful
--#region
-- Usefull scripts
SELECT * FROM sys.fn_builtin_permissions(default);
SELECT * FROM sys.fn_my_permissions('db2', 'DATABASE');
SELECT * FROM sys.fn_my_permissions('member', 'TABLE');
SELECT * FROM sys.fn_my_permissions('db2_key', 'SYMMETRIC KEY');
--Проверить, имеет ли пользователь конкретное разрешение на конкретный объект .
SELECT HAS_PERMS_BY_NAME('db2_key', 'SYMMETRIC KEY', 'CONTROL');
select * from sys.sql_modules;

-- SSMS Tools Pack для разделения регионов
--#endregion



/* Тут снова цепочки логические, нужен DMK and CERTIFICATE и дальше ключ бд и дальше ...
	Получается они иерархически друг друга перешифровывают, защита ключей ключами.
	OS, SQL SERVER, NETWORK encryption communication

	Symmetric encryption (shared secret)
	Asymmetric encryption (public key)
	Digital certificates (contain public key, comfortable for large-scale communication, like clients and application)
	Certification Authority
	Securing the network with TLS
	Data protection from the OS (SQL Server uses the Data Protection API (DPAPI) for Transparent Data Encryption (TDE).)

	Master keys in the encryption hierarchy (AES)

	CMK (COLUMN MASTER KEY)
	CEK (COLUMN Encryption KEY) */


/* The encryption hierarchy in detail

	Individual layers in the hierarchy can be accessed by apassword at the very least, unless an Extensible Key 
	Management (EKM) module is being used. The EKM module is a standalone device that holds symmetric and 
	asymmetric keys outside of SQL Server.

	The Database Master Key (DMK) is protected by the Service Master Key (SMK), and both of these are 
	symmetric keys. The SMK is created when you install SQL Server and is protected by the DPAPI.

	If you want to use TDE on your database, it requires a symmetric key called the 
	Database Encryption Key (DEK), which is protected by an asymmetric key in the EKM module or by a 
	certificate through the DMK. */
