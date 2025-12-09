

/* ================================================
   LIBRARY MANAGEMENT SYSTEM - FULL DEPLOYMENT FILE
   Version: 1.0
   Created: 2024-01-15
=================================================== */

----------------------------------------------------
-- STEP 1: CREATE DATABASE
----------------------------------------------------
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'LibraryDB')
BEGIN
    CREATE DATABASE LibraryDB;
END
GO

USE LibraryDB;
GO

----------------------------------------------------
-- STEP 2: CREATE TABLES
----------------------------------------------------

-- Authors table
CREATE TABLE Authors (
    AuthorID INT PRIMARY KEY IDENTITY(1,1),
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    BirthDate DATE,
    Email NVARCHAR(100),
    CreatedDate DATETIME DEFAULT GETDATE()
);

-- Books table
CREATE TABLE Books (
    BookID INT PRIMARY KEY IDENTITY(1,1),
    Title NVARCHAR(200) NOT NULL,
    AuthorID INT FOREIGN KEY REFERENCES Authors(AuthorID),
    ISBN NVARCHAR(20) UNIQUE,
    PublicationYear INT,
    Genre NVARCHAR(50),
    Quantity INT DEFAULT 1,
    AvailableQuantity INT,
    CreatedDate DATETIME DEFAULT GETDATE()
);

-- Members table
CREATE TABLE Members (
    MemberID INT PRIMARY KEY IDENTITY(1,1),
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    Email NVARCHAR(100) UNIQUE,
    Phone NVARCHAR(20),
    MembershipDate DATE DEFAULT GETDATE(),
    IsActive BIT DEFAULT 1
);

-- Loans table
CREATE TABLE Loans (
    LoanID INT PRIMARY KEY IDENTITY(1,1),
    BookID INT FOREIGN KEY REFERENCES Books(BookID),
    MemberID INT FOREIGN KEY REFERENCES Members(MemberID),
    LoanDate DATE DEFAULT GETDATE(),
    DueDate DATE,
    ReturnDate DATE,
    Status NVARCHAR(20) DEFAULT 'Borrowed',
    CONSTRAINT CHK_ReturnDate CHECK (ReturnDate IS NULL OR ReturnDate >= LoanDate)
);

----------------------------------------------------
-- STEP 3: INDEXES
----------------------------------------------------
CREATE INDEX IX_Books_AuthorID ON Books(AuthorID);
CREATE INDEX IX_Loans_BookID ON Loans(BookID);
CREATE INDEX IX_Loans_MemberID ON Loans(MemberID);
CREATE INDEX IX_Loans_Status ON Loans(Status);
CREATE INDEX IX_Members_Email ON Members(Email);

----------------------------------------------------
-- STEP 4: STORED PROCEDURES
----------------------------------------------------

-- Add Book Procedure
CREATE PROCEDURE sp_AddBook
    @Title NVARCHAR(200),
    @AuthorID INT,
    @ISBN NVARCHAR(20),
    @PublicationYear INT,
    @Genre NVARCHAR(50),
    @Quantity INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        INSERT INTO Books (Title, AuthorID, ISBN, PublicationYear, Genre, Quantity, AvailableQuantity)
        VALUES (@Title, @AuthorID, @ISBN, @PublicationYear, @Genre, @Quantity, @Quantity);

        SELECT 'Book added successfully' AS Message, SCOPE_IDENTITY() AS NewBookID;
    END TRY
    BEGIN CATCH
        SELECT ERROR_MESSAGE() AS ErrorMessage;
    END CATCH
END;
GO

-- Borrow Book Procedure
CREATE PROCEDURE sp_BorrowBook
    @BookID INT,
    @MemberID INT,
    @DueDays INT = 14
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRANSACTION;

    BEGIN TRY
        DECLARE @Available INT;
        SELECT @Available = AvailableQuantity FROM Books WHERE BookID = @BookID;

        IF @Available > 0
        BEGIN
            INSERT INTO Loans (BookID, MemberID, DueDate, Status)
            VALUES (@BookID, @MemberID, DATEADD(DAY, @DueDays, GETDATE()), 'Borrowed');

            UPDATE Books SET AvailableQuantity = AvailableQuantity - 1 WHERE BookID = @BookID;

            SELECT 'Book borrowed successfully' AS Message;
        END
        ELSE
        BEGIN
            SELECT 'Book is not available' AS Message;
        END

        COMMIT;
    END TRY
    BEGIN CATCH
        ROLLBACK;
        SELECT ERROR_MESSAGE() AS ErrorMessage;
    END CATCH
END;
GO

----------------------------------------------------
-- STEP 5: FUNCTIONS
----------------------------------------------------

-- Function: Calculate overdue days
CREATE FUNCTION fn_CalculateOverdueDays(@LoanID INT)
RETURNS INT
AS
BEGIN
    DECLARE @OverdueDays INT;

    SELECT @OverdueDays =
        CASE
            WHEN ReturnDate IS NULL AND DueDate < GETDATE()
            THEN DATEDIFF(DAY, DueDate, GETDATE())
            ELSE 0
        END
    FROM Loans WHERE LoanID = @LoanID;

    RETURN ISNULL(@OverdueDays, 0);
END;
GO

-- Function: Borrowed count
CREATE FUNCTION fn_GetMemberBorrowedCount(@MemberID INT)
RETURNS INT
AS
BEGIN
    DECLARE @Count INT;

    SELECT @Count = COUNT(*)
    FROM Loans
    WHERE MemberID = @MemberID AND Status = 'Borrowed';

    RETURN ISNULL(@Count, 0);
END;
GO

----------------------------------------------------
-- STEP 6: VIEWS
----------------------------------------------------

-- Active loans view
CREATE VIEW vw_ActiveLoans
AS
SELECT 
    l.LoanID,
    b.Title,
    CONCAT(a.FirstName, ' ', a.LastName) AS Author,
    CONCAT(m.FirstName, ' ', m.LastName) AS Member,
    l.LoanDate,
    l.DueDate,
    dbo.fn_CalculateOverdueDays(l.LoanID) AS OverdueDays
FROM Loans l
JOIN Books b ON l.BookID = b.BookID
JOIN Authors a ON b.AuthorID = a.AuthorID
JOIN Members m ON l.MemberID = m.MemberID
WHERE l.Status = 'Borrowed';
GO

-- Book inventory view
CREATE VIEW vw_BookInventory
AS
SELECT 
    b.BookID,
    b.Title,
    CONCAT(a.FirstName, ' ', a.LastName) AS Author,
    b.ISBN,
    b.Genre,
    b.Quantity,
    b.AvailableQuantity,
    (b.Quantity - b.AvailableQuantity) AS BorrowedCount
FROM Books b
JOIN Authors a ON b.AuthorID = a.AuthorID;
GO

----------------------------------------------------
-- STEP 7: SECURITY (ROLES + USERS + PERMISSIONS)
----------------------------------------------------

CREATE ROLE db_librarian;
CREATE ROLE db_member;
CREATE ROLE db_report_reader;

-- Replace with actual domain logins
-- CREATE USER librarian_user FOR LOGIN [YourDomain\librarian];
-- CREATE USER member_user FOR LOGIN [YourDomain\member];
-- CREATE USER report_user FOR LOGIN [YourDomain\reports];

-- Permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON Authors TO db_librarian;
GRANT SELECT, INSERT, UPDATE, DELETE ON Books TO db_librarian;
GRANT SELECT, INSERT, UPDATE, DELETE ON Members TO db_librarian;
GRANT SELECT, INSERT, UPDATE, DELETE ON Loans TO db_librarian;
GRANT EXECUTE ON sp_AddBook TO db_librarian;
GRANT EXECUTE ON sp_BorrowBook TO db_librarian;

GRANT SELECT ON vw_BookInventory TO db_member;
GRANT EXECUTE ON sp_BorrowBook TO db_member;

GRANT SELECT ON vw_ActiveLoans TO db_report_reader;
GRANT SELECT ON vw_BookInventory TO db_report_reader;

----------------------------------------------------
-- STEP 8: SAMPLE DATA
----------------------------------------------------

-- Authors
INSERT INTO Authors (FirstName, LastName, BirthDate, Email)
VALUES 
('George', 'Orwell', '1903-06-25', 'gorwell@example.com'),
('J.K.', 'Rowling', '1965-07-31', 'jkrowling@example.com'),
('Stephen', 'King', '1947-09-21', 'sking@example.com');

-- Books
EXEC sp_AddBook '1984', 1, '978-0451524935', 1949, 'Dystopian', 5;
EXEC sp_AddBook 'Harry Potter and the Philosopher''s Stone', 2, '978-0747532743', 1997, 'Fantasy', 10;
EXEC sp_AddBook 'The Shining', 3, '978-0307743657', 1977, 'Horror', 3;

-- Members
INSERT INTO Members (FirstName, LastName, Email, Phone)
VALUES
('John', 'Doe', 'john.doe@email.com', '555-0101'),
('Jane', 'Smith', 'jane.smith@email.com', '555-0102');

----------------------------------------------------
-- STEP 9: MAINTENANCE PROCEDURE
----------------------------------------------------
CREATE PROCEDURE sp_CleanupOldLoans
AS
BEGIN
    DELETE FROM Loans
    WHERE ReturnDate IS NOT NULL
    AND ReturnDate < DATEADD(YEAR, -5, GETDATE());
END;
GO

----------------------------------------------------
-- STEP 10: DOCUMENTATION
----------------------------------------------------
EXEC sp_addextendedproperty 
@name = N'Description', 
@value = 'Library Management System Database',
@level0type = N'DATABASE';

EXEC sp_addextendedproperty 
@name = N'Version', 
@value = '1.0',
@level0type = N'DATABASE';

EXEC sp_addextendedproperty 
@name = N'LastUpdated', 
@value = '2024-01-15',
@level0type = N'DATABASE';
GO