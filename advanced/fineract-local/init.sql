CREATE DATABASE IF NOT EXISTS fineract_default;
    CREATE DATABASE IF NOT EXISTS fineract_tenants;
    GRANT ALL PRIVILEGES ON fineract_default.* TO 'fineract'@'%';
    GRANT ALL PRIVILEGES ON fineract_tenants.* TO 'fineract'@'%';
    FLUSH PRIVILEGES;

