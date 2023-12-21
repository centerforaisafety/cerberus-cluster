CREATE DATABASE billing;

CREATE TABLE IF NOT EXISTS billing.accounts (
    account_id INT AUTO_INCREMENT PRIMARY KEY,
    account_name VARCHAR(255) NOT NULL,
    billing_details TEXT
);

CREATE TABLE IF NOT EXISTS billing.users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    account_id INT NOT NULL,
    user_name VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    FOREIGN KEY (account_id) REFERENCES accounts(account_id)
);

CREATE TABLE IF NOT EXISTS billing.resource_types (
    resource_type_id INT AUTO_INCREMENT PRIMARY KEY,
    resource_name VARCHAR(255) NOT NULL
);

CREATE TABLE IF NOT EXISTS billing.units_of_measure (
    unit_id INT AUTO_INCREMENT PRIMARY KEY,
    unit_name VARCHAR(50) NOT NULL,
    unit_description TEXT
);

CREATE TABLE IF NOT EXISTS billing.resource_specifications (
    resource_spec_id INT AUTO_INCREMENT PRIMARY KEY,
    resource_type_id INT NOT NULL,
    specification_name VARCHAR(255),
    unit_id INT,
    FOREIGN KEY (resource_type_id) REFERENCES resource_types(resource_type_id),
    FOREIGN KEY (unit_id) REFERENCES units_of_measure(unit_id)
);

CREATE TABLE IF NOT EXISTS billing.usage_records (
    usage_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    resource_spec_id INT NOT NULL,
    usage_start_time DATETIME NOT NULL,
    usage_end_time DATETIME NOT NULL,
    usage_amount BIGINT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (resource_spec_id) REFERENCES resource_specifications(resource_spec_id)
);

CREATE TABLE IF NOT EXISTS billing.pricing (
    pricing_id INT AUTO_INCREMENT PRIMARY KEY,
    account_id INT NOT NULL,
    resource_spec_id INT NOT NULL,
    price_per_unit DECIMAL(10, 2) NOT NULL,
    price_effective_date DATE NOT NULL,
    price_end_date DATE,
    FOREIGN KEY (account_id) REFERENCES accounts(account_id),
    FOREIGN KEY (resource_spec_id) REFERENCES resource_specifications(resource_spec_id)
);

-- Create user for logging
-- CREATE USER 'billing_logger' IDENTIFIED WITH mysql_native_password BY '{{ admin_password }}';

-- GRANT INSERT ON billing.usage_records TO 'billing_logger'@'%';

-- Insert units of measure
INSERT INTO billing.units_of_measure (unit_name, unit_description)
VALUES 
    ('bytes', 'Used for Network usage.'),
    ('bytes per second', 'Used for RAM usage.'),
    ('gigabytes', 'Used for Filesystem usage'),
    ('seconds', 'Used for GPU, CPU usage.');


-- Insert resource types
INSERT INTO billing.resource_types (resource_name)
VALUES
	('GPU', ),
	('CPU'),
	('RAM'),
	('Filesystem'),
    ('Network');

-- Insert resource specifications
INSERT INTO billing.resource_specifications (resource_type_id, specification_name, unit_id)
VALUES
	(1,'A100',4),
	(5,'Network Egress',1),
	(4,'Weka',3),
	(1,'H100',4);
