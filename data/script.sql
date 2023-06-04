CREATE TABLE people (
    execution_id INT NOT NULL,
    simulation_id INT,
    cycle INT,
    started_from_cycle INT DEFAULT 0,
    name VARCHAR(40),
    id INT,
    date_of_birth DATE,
    objective varchar(20) DEFAULT "resting",
    speed FLOAT DEFAULT -1.0,
    state INT DEFAULT 0,
    living_place INT DEFAULT -1,
    working_place INT DEFAULT -1,
    start_work_h INT DEFAULT -1,
    end_work_h INT DEFAULT -1,
    x FLOAT DEFAULT -1.0,
    y FLOAT DEFAULT -1.0
);

CREATE TABLE mosquitoes (
    execution_id INT NOT NULL,
    simulation_id INT NOT NULL,
    cycle INT,
    started_from_cycle INT DEFAULT 0,
    name VARCHAR(40),
    id INT,
    date_of_birth DATE,
    speed FLOAT DEFAULT -1.0,
    state INT DEFAULT 0,
    curr_building INT DEFAULT -1,
    bs_id INT DEFAULT -1,
    x FLOAT DEFAULT -1.0,
    y FLOAT DEFAULT -1.0
);

CREATE TABLE breeding_sites (
    execution_id INT NOT NULL,
    simulation_id INT NOT NULL,
    cycle INT,
    started_from_cycle INT DEFAULT 0,
    name VARCHAR(40),
    id INT,
    date_of_birth DATE,
    active BOOLEAN DEFAULT true,
    eggs INT DEFAULT -1,
    curr_building INT DEFAULT -1,
    x FLOAT DEFAULT -1.0,
    y FLOAT DEFAULT -1.0
);

CREATE TABLE eggs (
    execution_id INT NOT NULL,
    simulation_id INT NOT NULL,
    cycle INT,
    started_from_cycle INT DEFAULT 0,
    oviposition_date DATE,
    breeding_site INT,
    deposited_days INT
);

CREATE TABLE metrics (
    execution_id INT NOT NULL,
    simulation_id INT NOT NULL,
    cycle INT,
    started_from_cycle INT DEFAULT 0,
    specie varchar(30),
    susceptible int DEFAULT 0,
    exposed int DEFAULT 0,
    infected int DEFAULT 0,
    recovered int DEFAULT 0,
    dead int DEFAULT 0
);

drop table eggs;
drop table people;
drop table mosquitoes;
drop table breeding_sites;
drop table metrics;

select * from people where simulation_id = 1 and cycle = 0 and state = 1 ORDER BY cycle DESC;
update people SET speed=-1.0, living_place=-1,working_place=-1 where simulation_id = 1 and cycle = 0;

select * from metrics;