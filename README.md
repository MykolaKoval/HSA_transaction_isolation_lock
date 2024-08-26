# HSA transactions, isolation, locks
Understanding db transaction mechanic: blocking, isolation, locks

<h3>Isolation Levels. Summary.</h3>

| Isolation Level  | Description                                                                                                                                                                                                                         |
|------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Read Uncommitted | Same snapshot for all transactions (blocking is turned off). Performance takes priority over data consistency (transaction support not required, dirty reads tolerated).                                                            |
| Read Committed   | Every select within transaction creates own snapshot (transaction updates are visible in snapshot since it's always created from index). Required when actual data should be returned on read.                                      |
| Repeatable Read  | All selects within transaction read from same consistent snapshot (transaction updates are not visible in snapshot). Optimal for read heavy system (News, etc).                                                                     |
| Serializable     | Same as Repeatable Read with one difference for case when autocommit is off. Then all select work in blocking mode: SELECT ... LOCK IN SHARE MODE. Highest level of isolation, performance impact, higher risk to receive deadlock. |

<h3>Task</h3>

Reproduce isolation related phenomenons for [Percona Server](https://docs.percona.com/percona-server/8.0/index.html), [PostgreSQL](https://www.postgresql.org/docs/) databases:

| Problem             | Description                                                                                                                                |
|---------------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| Lost Update         | Write-write conflict when data is lost.                                                                                                    |
| Dirty Read          | Seeing uncommitted data that may disappear later.                                                                                          |
| Non-repeatable Read | Reading the same data twice within a transaction and getting different results due to changes committed by another transaction in between. |
| Phantom Read        | Seeing data rows that didn’t exist when a transaction started but were inserted by another transaction before it committed.                |

<h3>Environment</h3>

```
SET autocommit=0; disable auto commit after each request
SET GLOBAL innodb_status_output=ON; enable InnoDB standard Monitor
SET GLOBAL innodb_status_output_locks=ON; - enable Locks Monitor
```

<h3>Percona DB results:</h3>
```
// modify globally and reconnect
SELECT @@transaction_ISOLATION; // check for current seesion
SELECT @@global.transaction_ISOLATION;
set global transaction isolation level read committed;

```
https://dev.mysql.com/doc/refman/8.0/en/innodb-transaction-isolation-levels.html
https://docs.percona.com/percona-server/innovation-release/isolation-levels.html

| Isolation Level  | lost update | dirty read | non-repeatable read | phantom read |
|------------------|-------------|------------|---------------------|--------------|
| Read Uncommitted | Y           | Y          | Y                   | Y            |
| Read Committed   | Y           | N          | Y                   | Y            |
| Repeatable Read  | N           | N          | Y                   | N            |
| Serializable     | N           | N          | N                   | N            |

<h3>PostgreSQL DB results:</h3>
```
// psql connection
docker exec -it hsa_transaction_isolation_lock-postgresql-1 psql -U user -d test_db

// modify globally and reconnect
SHOW default_transaction_isolation;
ALTER DATABASE test_db SET DEFAULT_TRANSACTION_ISOLATION TO 'repeatable read';
```
https://www.postgresql.org/docs/current/transaction-iso.html

| Isolation Level  | lost update | dirty read | non-repeatable read | phantom read |
|------------------|-------------|------------|---------------------|--------------|
| Read Uncommitted | N/A         | N/A        | N/A                 | N/A          |
| Read Committed   | Y           | N          | Y                   | Y            |
| Repeatable Read  | N           | N          | N                   | N            |
| Serializable     | N           | N          | N                   | N            |

<h4>Scenario details: Lost Update</h4>

Both T1 and T2 transactions concurrently updating same column ``balance``

| T1                 | T2                 | Database  | Query                                            |
|--------------------|--------------------|-----------|--------------------------------------------------|
| BEGIN              | BEGIN              | 100       |                                                  |
| read               | read               | 100       | ``select balance from users where user_id=1``    |
| update balance=150 |                    |           | ``update users set balance=150 where user_id=1`` |
|                    | update balance=125 |           | ``update users set balance=125 where user_id=1`` |
| commit             |                    |           |                                                  |
| read               |                    | 150       | ``select balance from users where user_id=1``    |
|                    | commit             |           |                                                  |
|                    | read               | 125       | ``select balance from users where user_id=1``    |
| read               |                    | 125       | Lost Update for T1!!                             |

<h4>Scenario details: Dirty Read</h4>

T2 see uncommited changes of T1

| T1                 | T2     | Database | Query                                            |
|--------------------|--------|----------|--------------------------------------------------|
| BEGIN              | BEGIN  | 100      |                                                  |
| read               | read   | 100      | ``select balance from users where user_id=1``    |
| update balance=150 |        |          | ``update users set balance=150 where user_id=1`` |
|                    | read   | 150      | ``select balance from users where user_id=1``    |
|                    | commit |          |                                                  |
| rollback           |        |          |                                                  |
| read               |        | 100      | ``select balance from users where user_id=1``    |
|                    | read   | 100      | ``select balance from users where user_id=1``    |

<h4>Scenario details: Non-repeatable Read</h4>

T2 see commited changes of T1 in scope of transaction

| T1                 | T2                            | Database | Query                                                      |
|--------------------|-------------------------------|----------|------------------------------------------------------------|
| BEGIN              | BEGIN                         | 100      |                                                            |
| read               | read                          | 100      | ``select balance from users where user_id=1``              |
| update balance=150 |                               |          | ``update users set balance=150 where user_id=1``           |
| commit             |                               |          |                                                            |
|                    | update balance = balance + 10 |          | ``update users set balance= balance + 10 where user_id=1`` |
|                    | read                          | 160      | ``select balance from users where user_id=1``              |

<h4>Scenario details: Phantom Read</h4>

T2 see inserted records of T1 in scope of transaction

| T1            | T2        | Database | Query                                                                         |
|---------------|-----------|----------|-------------------------------------------------------------------------------|
| BEGIN         | BEGIN     | 1        |                                                                               |
| read all      | read all  | 1        | ``select * from users where balance=100``                                     |
| insert record |           |          | ``insert into users (name, city, balance) values ('Dmytro', 'Dnipro', 100);`` |
| commit        |           |          |                                                                               |
|               | read all  | 2        | ``select * from users where balance=100``                                     |