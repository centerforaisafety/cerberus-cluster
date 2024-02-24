CREATE DATABASE billing;

CREATE TABLE IF NOT EXISTS billing.accounts (
    account_id INT AUTO_INCREMENT PRIMARY KEY,
    account_name VARCHAR(255) NOT NULL,
    billing_details TEXT,
    email VARCHAR(255),
    billing_address TEXT,
    created_date DATE NOT NULL DEFAULT (CURRENT_DATE),
    archived BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS billing.users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    account_id INT NOT NULL,
    user_name VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    FOREIGN KEY (account_id) REFERENCES billing.accounts(account_id),
    created_date DATE NOT NULL DEFAULT (CURRENT_DATE),
    archived BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS billing.measurement_units (
    measurement_unit_id INT AUTO_INCREMENT PRIMARY KEY,
    measurement_unit_name VARCHAR(50) NOT NULL,
    measurement_unit_description TEXT
);

CREATE TABLE IF NOT EXISTS billing.resource_types (
    resource_type_id INT AUTO_INCREMENT PRIMARY KEY,
    resource_name VARCHAR(255) NOT NULL,
    resource_description TEXT,
    measurement_unit_id INT,
    FOREIGN KEY (measurement_unit_id) REFERENCES billing.measurement_units(measurement_unit_id)
);

CREATE TABLE IF NOT EXISTS billing.resource_specifications (
    resource_spec_id INT AUTO_INCREMENT PRIMARY KEY,
    resource_type_id INT NOT NULL,
    specification_name VARCHAR(255),
    FOREIGN KEY (resource_type_id) REFERENCES billing.resource_types(resource_type_id)
);

CREATE TABLE IF NOT EXISTS billing.usage_records (
    usage_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    resource_spec_id INT NOT NULL,
    usage_start_time DATETIME NOT NULL,
    usage_end_time DATETIME NOT NULL,
    usage_amount BIGINT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES billing.users(user_id),
    FOREIGN KEY (resource_spec_id) REFERENCES billing.resource_specifications(resource_spec_id)
);

CREATE TABLE IF NOT EXISTS billing.pricing (
    pricing_id INT AUTO_INCREMENT PRIMARY KEY,
    account_id INT NOT NULL,
    resource_spec_id INT NOT NULL,
    price_per_unit DECIMAL(10, 2) NOT NULL,
    price_effective_date DATE NOT NULL,
    price_end_date DATE,
    FOREIGN KEY (account_id) REFERENCES billing.accounts(account_id),
    FOREIGN KEY (resource_spec_id) REFERENCES billing.resource_specifications(resource_spec_id)
);

-- Insert units of measure
INSERT INTO billing.measurement_units (measurement_unit_name, measurement_unit_description)
VALUES 
    ('bytes', 'Used for Filesystem, Network usage.'),
    ('bytes per second', 'Used for RAM usage.'),
    ('seconds', 'Used for GPU, CPU usage.');


-- Insert resource types
INSERT INTO billing.resource_types (resource_name, measurement_unit_id)
VALUES
	('GPU', 3),
	('CPU', 3),
	('RAM', 2),
	('Filesystem', 1),
    ('Network', 1);

-- Insert resource specifications
INSERT INTO billing.resource_specifications (resource_type_id, specification_name)
VALUES
	(1, 'A100'),
	(5, 'Compute Node Egress'),
	(4, 'Weka'),
	(1, 'H100'),
    (5, 'Login Node Egress');
