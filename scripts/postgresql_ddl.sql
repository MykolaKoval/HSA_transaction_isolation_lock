CREATE TABLE IF NOT EXISTS users (
    user_id SERIAL PRIMARY KEY,
    name VARCHAR(10),
    city VARCHAR(10),
    balance INTEGER
);
