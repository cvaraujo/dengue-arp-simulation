/**
* Name: Dengue Spread Simulation
* Author: Carlos V. D. Araújo
* Description:
* Tags: gis, shapefile, graph, skill, health, logistics
*/

model DenguePropagation

global {	
	// ----------------------------------------------------------
	// ------------------- Simulation Config --------------------
	// ----------------------------------------------------------
	//SQLite
	string sqlite_ds <- "/home/araujo/Documents/dengue-arp-simulation/data/dengue-propagation.db";
	map<string, string> POSTGRES <- [
     'host'::'localhost',
     'dbtype'::'postgres',
     'database'::'dengue-propagation',
     'port'::'5432',
     'user'::'araujo',
     'passwd'::'admin']; 
	//["dbtype"::"sqlite", "database"::sqlite_ds];
	// Step size
	float step <- 12 #h;
	// Start date string
	string start_date_str <- "2023-01-01";
	// Simulation start date
	date starting_date <- date(start_date_str + ", 05:00 AM", "yyyy-MM-dd, hh:mm a");	
	// Max number of cycles
	int max_cycles <- 60;
	// Scenario
	int scenario_id <- 1;
	// Map network
	graph road_network;
	// Load data from old simulation
	bool use_initial_scenario <- true;
	
	// Start from cycle
	int start_from_execution_id <- 1;
	int start_from_cycle <- 0;
	int start_from_scenario <- 1;
	// Batch end simulation
	bool end_simulation <- false;
	// Parameter to differ the batch execution 
	string simulation_name update: self.name;
	// Primary execution id to save
	int execution_id <- 1;
	bool run_batch <- false;
	bool save_states <- false;

	// Default number of species
	int nb_people <- 14;
	int nb_breeding_sites <- 3;
	int nb_mosquitoes <- 20;
	int nb_infected_people <- 15;
	int nb_infected_mosquitoes <- 20;
	
	// Counter of species
	int cnt_people <- 0;
	int cnt_breeding_sites <- 0;
	int cnt_mosquitoes <- 0;
	
	list<int> cycle_exposed_people <- list_with(max_cycles+1, 0);
	list<int> cycle_infected_people <- list_with(max_cycles+1, 0);
	list<int> cycle_recovered_people <- list_with(max_cycles+1, 0);
	
	// ----------------------------------------------------------
	// ----------------------- Map data -------------------------
	// ----------------------------------------------------------
	// Filename of buildings and roads
	string default_shp_dir <- "../includes";
	string node_filename <- default_shp_dir + "/nodes.shp";
	string road_filename <- default_shp_dir + "/edges.shp";
	string building_filename <- default_shp_dir + "/buildings.shp";	
	
	// Shapefile of the roads 
	file road_shapefile <- file(road_filename);
	// Shapefile of the intersections between roads
	file node_shapefile <- file(node_filename);
	// Shapefile of the buildings (blocks)
	file building_shapefile;
	
	//Shape of the environment
	geometry shape <- envelope(road_shapefile);
	
	// ----------------------------------------------------------
	// ---------------- People global parameters ----------------
	// ----------------------------------------------------------
	// Start-end work time
	int min_work_start <- 5;
	int max_work_start <- 8;
	int min_work_end <- 16;
	int max_work_end <- 19;
	
	// Speed
	float people_min_speed <- 20.0 #km / #h;
	float people_max_speed <- 60.0 #km / #h;
	
	// Recovery rate
	float people_daily_recovery_rate <- 0.143; // TODO: remove 0's
	
	// ----------------------------------------------------------
	// -------------- Mosquitoes global parameters --------------
	// ----------------------------------------------------------	
	// Speed
	float mosquitoes_min_speed <- 1.5 #km / #h;
	float mosquitoes_max_speed <- 2.5 #km / #h;
	
	// Probabilities
	float mosquitoes_daily_rate_of_bites <- 0.168;
	float mosquitoes_frac_infectious_bites <- 0.6;
	float mosquitoes_daily_latency_rate	<- 0.143;
	float mosquitoes_susceptibility_to_dengue <- 0.526;
	float mosquitoes_death_rate <- 0.01;
	float mosquitoes_oviposition_rate <- 0.02;
	
	// Movement
	float mosquitoes_move_probability <- 0.8;
	
	// Oviposition capacity
	int mosquitoes_max_carrying_capacity <- 2;
	// Max move distance
	float max_move_radius <- 150.0 #m;
	
	// ----------------------------------------------------------
	// ------------- Breeding site global parameters ------------
	// ----------------------------------------------------------
		
	// Breeding Sites global parameters
	float bs_eggs_to_mosquitoes <- 0.125; // 0.15 / 2
	float bs_aquatic_phase_mortality_rate <- 0.066; // 0.05
	
	// ----------------------------------------------------------
	// --------------- Logistics global parameters --------------
	// ----------------------------------------------------------
	float mosquito_insecticide_efficiency <- 0.7;
	float bs_insecticide_efficiency <- 0.1;

	// ----------------------------------------------------------
	// -------------------- Global actions ----------------------
	// ----------------------------------------------------------
	reflex stop_simulation when: (start_from_cycle + cycle) >= max_cycles {
		ask Saver {
			do close;
		}
		
	   end_simulation <- true;
	}
	
	action create_street_blocks_and_save {
		// Create blocks
		// Get the number of blocks
		int num_blocks <- Roads max_of(each.block_id);
		
		loop i from: 1 to: num_blocks {
			// Get the roads and vertices of the block
			list<Roads> block_roads <- Roads where (each.block_id = i);
			list nodes <- block_roads collect([each.u, each.v]);
									
			list sequence <- [one_of(Vertices where(each.osmid = nodes[0][1]))];

			// Get the right sequence of arcs (streets) 
			bool has_change <- true;
			loop while: length(sequence) < length(nodes) and has_change {
				has_change <- false;
				loop j from: 1 to: length(nodes)-1 {
					if(one_of(Vertices where(each.osmid = nodes[j][0])).name = sequence[length(sequence)-1].name) {
						add one_of(Vertices where(each.osmid = nodes[j][1])) to: sequence;
						has_change <- true;
					}
				}
			}
			
			// Converte the sequence of vertices into points
			list<point> points <- sequence collect(
				point(each.location.x, each.location.y)
			);
	
			create Blocks {
				id <- i;
				block_polygon <- envelope(polygon(points));
			}
		}
			
		list<Blocks> valid_blocks <- Blocks where(each.block_polygon.area > 0);
						
		ask valid_blocks {
			create Buildings from: [block_polygon] with: [id::id];
		}
		
		save Buildings to: building_filename type: shp attributes: ["name", "id", "location"] crs: "EPSG:4326";
	}
	
	action create_starting_scenario {
		// Creating Breeding sites	
		create BreedingSites number: nb_breeding_sites {
			building_location <- one_of(Buildings);
			location <- any_location_in(building_location);
			buildings <- [building_location] + Buildings at_distance(max_move_radius);
			new_eggs <- rnd(0, 1) * mosquitoes_max_carrying_capacity;
		}
		
		// Creating Mosquitoes
		// Infected
		create Mosquitoes number: nb_infected_mosquitoes {
			breeding_site <- one_of(BreedingSites);
			current_building <- one_of(breeding_site.buildings);
			location <- any_location_in(current_building);
			state <- 2;
		}
		
		// Susceptible
		create Mosquitoes number: nb_mosquitoes {
			breeding_site <- one_of(BreedingSites);
			current_building <- one_of(breeding_site.buildings);
			location <- any_location_in(current_building);
			state <- 0;
		}

		// Create people
		// Infected			
		create People number: nb_infected_people {
			living_place <- one_of(Buildings);
			working_place <- one_of(Buildings);
			location <- any_location_in(living_place);
			start_work <- rnd(min_work_start, max_work_start);
			end_work <- rnd(min_work_end, max_work_end);
			state <- 1;
		}
		
		// Susceptible
		create People number: nb_people {
			living_place <- one_of(Buildings);
			working_place <- one_of(Buildings);
			location <- any_location_in(living_place);
			start_work <- rnd(min_work_start, max_work_start);
			end_work <- rnd(min_work_end, max_work_end);
			state <- 0;
		}
		cycle_infected_people[0] <- nb_infected_people;
		cycle_exposed_people[0] <- nb_people;
	}
	
	action update_start_scenario {
		int n <- 0;
		
		ask Saver {
			if (!self.isConnected()) {
				do connect (params: POSTGRES);
			}
		}
		
		string delete_query <- "";
		loop spc over: ["mosquitoes", "people", "breeding_sites", "eggs"] {
			delete_query <- delete_query + "delete from " + spc + " where execution_id=" + string(start_from_execution_id) +
			" and simulation_id=" + string(start_from_scenario) + " and cycle=" + string(start_from_cycle) + "; ";
			}
					

		ask Saver {
			do executeUpdate(
				updateComm: delete_query
			);
		}
				
		// --------------------------------- Mosquitoes ---------------------------------
		string prefix <- "(" + string(start_from_execution_id) + ", " + string(start_from_scenario) + ", " + string(start_from_cycle + cycle) + ", " + string(start_from_cycle);
				
		string query_mosquitoes <- "INSERT INTO mosquitoes(execution_id, simulation_id, cycle, 
			started_from_cycle, name, id, date_of_birth, speed, state, curr_building, bs_id, x, y) VALUES";
		
		int cnt <- 1;
		int nb <- length(Mosquitoes);
				
		ask Mosquitoes {
			query_mosquitoes <- query_mosquitoes + prefix + ", '" + self.name + "', " + string(self.id) + ", '" + string(self.date_of_birth) +
			"' , " + string(self.speed) + ", " + string(self.state) + ", " + string(self.current_building.id) +
			", " + string(self.breeding_site.id) + ", " + string(self.location.x) + ", " + string(self.location.y) + ")";
			if cnt < nb {
				query_mosquitoes <- query_mosquitoes + ", ";
			} else {
				query_mosquitoes <- query_mosquitoes + "; ";
			}
			cnt <- cnt + 1;
		}
		
		// --------------------------------- People ---------------------------------	
		string query_people <- "INSERT INTO people(execution_id, simulation_id, cycle, 
			started_from_cycle, name, id, date_of_birth, objective, speed, state, living_place,
			working_place, start_work_h, end_work_h, x, y) VALUES";
		
		cnt <- 1;
		nb <- length(People);
		
		ask People {
			query_people <- query_people + prefix + ", '" + string(self.name) + "', " + string(self.id) + ", '" + string(starting_date) +
				"', '" + self.objective + "', " + string(self.speed) + ", " + string(self.state) + ", " + string(self.living_place.id) +
				", " + string(self.working_place.id) + ", " + string(self.start_work) + ", " + string(self.end_work) + 
				", " + string(self.location.x) + ", " + string(self.location.y) + ")";
			
			if cnt < nb {
				query_people <- query_people + ", ";
			} else {
				query_people <- query_people + "; ";
			}
			cnt <- cnt + 1;
		}
		
		// --------------------------------- Breeding Sites ---------------------------------	
		string query_bs <- "INSERT INTO breeding_sites(execution_id, simulation_id, cycle, 
			started_from_cycle, name, id, date_of_birth, active, eggs, curr_building, x, y) VALUES";
	
		cnt <- 1;
		nb <- length(BreedingSites);
		
		ask BreedingSites {
			query_bs <- query_bs + prefix + ", '" + string(self.name) + "', " + string(self.id) + ", '" + string(starting_date) +
				"', " + string(self.active) + ", " + string(self.eggs) + ", " + string(self.building_location.id) +
				", " + string(self.location.x) + ", " + string(self.location.y) + ")";
			
			if cnt < nb {
				query_bs <- query_bs + ", ";
			} else {
				query_bs <- query_bs + "; ";
			}
			cnt <- cnt + 1;
		}
		
		ask Saver {
			do executeUpdate(
				updateComm: query_mosquitoes + query_people + query_bs
			);
		do close;
		}
	}
	
	action load_starting_scenario {		
		bool fill_data <- false;
				
		ask Saver {			
			list<list> breeding_sites <- self.select(
				select: "SELECT * FROM breeding_sites where (execution_id=? and simulation_id=? and cycle=?);",
				values:[start_from_execution_id, start_from_scenario, start_from_cycle]
			);
						
			nb_breeding_sites <- 0;
			loop bs over: breeding_sites[2] {
				string load_name <- bs[4];
				int load_id <- int(bs[5]);
				date load_date_birth <- date(bs[6]);
				bool load_active <- bool(bs[7]);
				int load_eggs <- int(bs[8]);
				int load_building <- int(bs[9]);
				float load_x <- float(bs[10]);
				float load_y <- float(bs[11]);
				
				nb_breeding_sites <- nb_breeding_sites + 1;
				
				if (load_x = -1 or load_y = -1 or load_building = -1) {
					fill_data <- true;
				}
																
				create BreedingSites {
					name <- load_name;
					id <- load_id;
					active <- load_active;
					eggs <- load_eggs;
					building_location <- load_building != -1 ? one_of(Buildings where (each.id = load_building)) : one_of(Buildings);
					location <- (load_x != -1.0 and load_y != -1.0) ? point(load_x, load_y) : any_location_in(building_location);
					buildings <- Buildings at_distance(max_move_radius);
				}
				// ----------------------------------------------------------------------------------
				// ----------------------------------------------------------------------------------
				// ----------------------------------------------------------------------------------
				// ----------------------------------------------------------------------------------
				// ----------------------------------------------------------------------------------
			}
			cnt_breeding_sites <- nb_breeding_sites;
			
			// ----------------------------------------------------------
			list<list> people <- self.select(
				select: "SELECT * FROM people where (execution_id=? and simulation_id=? and cycle=?);",
				values:[start_from_execution_id, start_from_scenario, start_from_cycle]
			);
			
			nb_infected_people <- 0;
			nb_people <- 0;
			int nb_recovered_people <- 0;
			loop person over: people[2] {
				string load_name <- person[4];
				int load_id <- int(person[5]);
				string load_obj <- person[7];
				float load_speed <- float(person[8]);
				int load_state <- int(person[9]);
				int lp <- int(person[10]);
				int wp <- int(person[11]);
				int sw <- int(person[12]);
				int ew <- int(person[13]);
				float load_x <- float(person[14]);
				float load_y <- float(person[15]);
				
				if (load_x = -1 or load_y = -1 or load_speed = -1 or lp = -1 or wp = -1) {
					fill_data <- true;
				}
				
				if load_state = 1 {
					nb_infected_people <- nb_infected_people + 1;
				} else if load_state = 0 {
					nb_people <- nb_people + 1;	
				} else {
					nb_recovered_people <- nb_recovered_people + 1;
				}
				
				create People {
					name <- load_name;
					id <- load_id;
					objective <- load_obj;
					speed <- load_speed != -1 ? load_speed : rnd(people_min_speed, people_max_speed) #km / #h;
					state <- load_state;
					living_place <- lp != -1 ? one_of(Buildings where (each.id = lp)) : one_of(Buildings);
					working_place <- wp != -1 ? one_of(Buildings where (each.id = wp)) : one_of(Buildings);
					start_work <- sw != -1 ? sw : rnd(min_work_start, max_work_start);
					end_work <- ew != -1 ? ew : rnd(min_work_end, max_work_end);
					location <- (load_x != -1.0 and load_y != -1.0) ? point(load_x, load_y) : any_location_in(living_place);
					start_infected <- load_state = 1 ? true : false;
				}
			}
			cnt_people <- nb_people + nb_infected_people + nb_recovered_people;
//			cycle_infected_people[start_from_cycle] <- nb_infected_people;
//			cycle_exposed_people[start_from_cycle] <- nb_people;
//			cycle_recovered_people[start_from_cycle] <- nb_recovered_people;			
			
			// ----------------------------------------------------------
			list<list> mosquitoes <- self.select(
				select: "SELECT * FROM mosquitoes where (execution_id=? and simulation_id=? and cycle=?);",
				values:[start_from_execution_id, start_from_scenario, start_from_cycle]
			);
			
			nb_mosquitoes <- 0;
			nb_infected_mosquitoes <- 0;
			loop mosquito over: mosquitoes[2] {
				string load_name <- mosquito[4];
				int load_id <- int(mosquito[5]);
				date load_date_birth <- date(mosquito[6]);
				float load_speed <- float(mosquito[7]);
				int load_state <- int(mosquito[8]);
				int load_building <- int(mosquito[9]);
				int load_bs <- int(mosquito[10]);
				float load_x <- float(mosquito[11]);
				float load_y <- float(mosquito[12]);
				
				if (load_x = -1 or load_speed = -1.0 or load_building = -1) {
					fill_data <- true;
				}
				
				if load_id > cnt_mosquitoes {
					cnt_mosquitoes <- load_id + 1;
				}
				
				if load_state = 2 {
					nb_infected_mosquitoes <- nb_infected_mosquitoes + 1;
				} else {
					nb_mosquitoes <- nb_mosquitoes + 1;	
				}
				
				create Mosquitoes {
					name <- load_name;
					id <- load_id;
					speed <- load_speed != -1.0 ? load_speed : rnd(mosquitoes_min_speed, mosquitoes_max_speed) #km / #h;
					state <- load_state;
					current_building <- load_building != -1 ? one_of(Buildings where (each.id = load_building)) : one_of(Buildings);
					breeding_site <- load_bs != -1 ? one_of(BreedingSites where (each.id = load_bs)) : one_of(BreedingSites);
					location <- (load_x != -1.0 and load_y != -1.0) ? point(load_x, load_y) : any_location_in(current_building);
				}
			}
			
			// ----------------------------------------------------------
			list<list> eggs <- self.select(
				select: "SELECT * FROM eggs where (execution_id=? and simulation_id=? and cycle=?);",
				values:[start_from_execution_id, start_from_scenario, start_from_cycle]
			);
			
			loop egg over: eggs[2] {
				create Eggs {
					deposited_date <- date(egg[4]);
					breeding_site <- one_of(BreedingSites where (each.id = int(egg[5])));
					deposited_days <- float(egg[6]);
					
				}
			}
		}
		
		if fill_data {
			do update_start_scenario;
		}
	}
	
	// ----------------------------------------------------------
	// ----------------------- Init Model -----------------------
	// ----------------------------------------------------------
	init {
		// End the simulation if no map was provided
		if !file_exists(node_filename) or !file_exists(road_filename) {
			do die;
		}
						
		// Vertex
		create Vertices from: node_shapefile with: [osmid::string(read("osmid"))];
		
		// Load the roads
		create Roads from: road_shapefile with: [
			osmid::read("osmid"),
			id::int(read("id_key")),
			block_id::int(read("block")),
			u::read("u"),
			v::read("v")
		];
						
		// Define the network graph
		road_network <- as_driving_graph(Roads, Vertices);
		
		// Create the street blocks that turns into Buildings
		// Specie to save the others
		if !file_exists(building_filename) {
			do create_street_blocks_and_save;			
		} else {
			building_shapefile <- file(building_filename);
			create Buildings from: building_shapefile with: [name::read("name"), id::int(read("id")), location::read("location")];
		}
		
		if use_initial_scenario {
			
			create Saver{}
						
			ask Saver {
				if (!self.isConnected()) {
					do setParameter params: POSTGRES;
		            do connect params: self.getParameter();
				}
			}
						
			do load_starting_scenario;
		} else {
			do create_starting_scenario;
			create Saver{}
			ask Saver {
				do connect(params: POSTGRES);
			}
		}
		
		write "Model loaded...";
	}
}

species Eggs {
	// Breeding site
	BreedingSites breeding_site;
	// Deposited day
	float deposited_days <- 0.0;
	//
	date deposited_date <- current_date;
	
	reflex turn_mosquito when: every(cycle) {
		if flip(bs_eggs_to_mosquitoes) {
			// Create a new mosquito
			create Mosquitoes {
				breeding_site <- myself.breeding_site;
				current_building <- one_of(breeding_site.buildings);
				location <- any_location_in(current_building);
				state <- 0; 
			}
			breeding_site.eggs <- breeding_site.eggs - 1;
			do die;
		}
	}
	
	reflex die when: flip(bs_aquatic_phase_mortality_rate) {
		breeding_site.eggs <- breeding_site.eggs - 1;
		do die;
	}
}

// Species to represent the Breeding Sites
species BreedingSites {
	// Id
	int id <- -1;
	// Location
	point location;
	// If the breeding ground can generate mosquitoes
	bool active <- true;
	// Number of eggs
	int eggs <- 0;
	// Building
	Buildings building_location;
	// Buildings in the risk area of this breeding site
	list<Buildings> buildings;
	// Eggs to crete the species
	int new_eggs <- 0;
	
	init {
		// Update ID and count of species
		if id = -1 {
			id <- cnt_breeding_sites;
			cnt_breeding_sites <- cnt_breeding_sites + 1;
		}
	}
	
	reflex create_new_eggs when: new_eggs > 0 {
		eggs <- eggs + new_eggs;
		create Eggs number: new_eggs {
			breeding_site <- myself;
		}
		new_eggs <- 0;
	}
	
	aspect default {
		draw circle(30) color: #black;
	}		
}

// Species to represent the people using the skill moving
species People skills: [moving]{
	// id
	int id <- -1;
	// Objective (resting or working)
	string objective <- "resting";
	int start_work <- -1;
	int end_work <- -1;
	point location;
	Buildings living_place;
	Buildings working_place;
	point target;
	float speed <- rnd(people_min_speed, people_max_speed) #km / #h;
	// (SIR) Current state (susceptible = 0, infected = 1 or recovered = 2)
	int state <- 0;
	bool start_infected <- false;
	
	init {
		if id = -1 {
			id <- cnt_people;
			cnt_people <- cnt_people + 1;
		}
	}
	
	// Reflex to go working
	reflex time_to_work when: current_date.hour >= start_work and objective = "resting" {
		objective <- "working";
		target <- any_location_in(working_place);
	}
	
	// Reflex to go back to home
	reflex time_to_go_home when: current_date.hour >= end_work and objective = "working" {
		objective <- "resting";
		target <- any_location_in(living_place);
	}
	
	// Reflex to move to the target building
	reflex move when: target != nil {
		//we use the return_path facet to return the path followed
		do goto (target: target, on: Roads, recompute_path: false, return_path: false);
		
		if (location = target) {
			target <- nil;
		}	
	}
	
	// Reflex to change the state of the agent to infected
	reflex change_to_infected_state when: state = 0 {
		float proba <- 1 - (1 - mosquitoes_daily_rate_of_bites * mosquitoes_susceptibility_to_dengue);
		ask Mosquitoes at_distance(1 #m) {
			// Check the mosquitoes state
			if state = 2 and flip(proba){
				myself.state <- 1;
				cycle_infected_people[(start_from_cycle + cycle)] <- cycle_infected_people[(start_from_cycle + cycle)] + 1;
			}
		}
	}
	
	// Reflex to change the state of the agent to recovered
	reflex change_to_recovered_state when: state = 1 and flip(people_daily_recovery_rate) {
		state <- 2;
		cycle_recovered_people[(start_from_cycle + cycle)] <- cycle_recovered_people[(start_from_cycle + cycle)] + 1;
		do die;
	}
	
	aspect default {
		if state = 0 {
			draw circle(5) color: #yellow;	
		} else if state = 1 {
			draw circle(5) color: #red;
		} else {
			draw circle(5) color: #green;
		}	
	}
}

// Species to represent the mosquitoes using the skill moving
species Mosquitoes skills: [moving] {
	// Id
	int id <- -1;
	// Default speed of the agent
	float speed <- rnd(mosquitoes_min_speed, mosquitoes_max_speed) #km / #h;
	// (SEI) State (susceptible = 0, exposed = 1 or infected = 2)
	int state <- 0;
	// Target
	point target;
	// Current location
	point location;
	// Start outbreak location
	BreedingSites breeding_site <- nil;
	// Current road
	Buildings current_building;
	//
	date date_of_birth <- current_date;
	
	init {
		if id = -1 {
			id <- cnt_mosquitoes;
			name <- "mosquitoes" + string(cnt_mosquitoes);
			cnt_mosquitoes <- cnt_mosquitoes + 1;
		}
	}

	// Reflex to stay in current location or select a random destination
	reflex random_move	when: (target = nil) and (flip(mosquitoes_move_probability)) {
		current_building <- one_of(breeding_site.buildings);
		target <- any_location_in(current_building);
	}
	
	// Reflex to move to the target building
	reflex move when: target != nil {
		//we use the return_path facet to return the path followed
		do goto (target: target, on: Roads, recompute_path: false, return_path: false);
		
		if (location = target) {
			target <- nil;
		}	
	}
	
	// Reflex to change the state of the agent to exposed
	reflex change_to_exposed_state when: state = 0 {
		float proba <- 1 - (1 - mosquitoes_daily_rate_of_bites * mosquitoes_susceptibility_to_dengue);
		ask People at_distance(1 #m) {
			// Check the people state
			if state = 1 and flip(proba){
				myself.state <- 1;
			}
		}
	}
	
	// Reflex to change the state of the agent to infected
	reflex change_to_infected_state when: state = 1 and flip(mosquitoes_daily_latency_rate) {
		state <- 2;
	}
	
	reflex die when: flip(mosquitoes_death_rate) {
		do die;
	}
	
	// Reflex to generate a new offspring
	reflex oviposition when: flip(mosquitoes_oviposition_rate){
		BreedingSites potential_bs <- BreedingSites at_distance(1 #m) closest_to(self);
		if potential_bs != nil {
			potential_bs.new_eggs <- rnd(1, mosquitoes_max_carrying_capacity);
		}
	}
	
	aspect default {
		if state <= 1 {
			draw circle(5) color: #red;
		} else if state = 2 {
			draw circle(5) color: #red;
		} else {
			draw circle(5) color: #red;
		}
	}
}

//Species to represent the buildings
species Buildings {
	int id <- -1;
	string name;
	point location;
	list<point> road_streets;
	
	aspect default {
		draw shape color: #gray;
	}
}

//Species to represent the roads
species Vertices skills: [intersection_skill] {
	string osmid;
	
	aspect default {
		draw circle(5) color: #black;
	}
}

species Roads skills: [road_skill] {
	string osmid;
	int id;
	int block_id;
	string u;
	string v;
	
	aspect default {
		draw shape color: #black;
	}
}

species Blocks {
	int id <- -1;
	geometry block_polygon;
}

species Saver parent: AgentDB {
	action save_species {		
		if run_batch {
			list<string> simulation_id <- simulation_name split_with ' ';
			scenario_id <- int(simulation_id[1]) + 1;
		}
				
		// --------------------------------- Mosquitoes ---------------------------------
		string prefix <- "(" + string(execution_id) + ", " + string(scenario_id) + ", " + string(start_from_cycle + cycle) + ", " + string(start_from_cycle);
		
		
		string query_mosquitoes <- "INSERT INTO mosquitoes(execution_id, simulation_id, cycle, 
			started_from_cycle, name, id, date_of_birth, speed, state, curr_building, bs_id, x, y) VALUES";
		
		int cnt <- 1;
		int nb <- length(Mosquitoes);
		
		ask Mosquitoes {
			query_mosquitoes <- query_mosquitoes + prefix + ", '" + self.name + "', " + string(self.id) + ", '" + string(self.date_of_birth) +
			"' , " + string(self.speed) + ", " + string(self.state) + ", " + string(self.current_building.id) +
			", " + string(self.breeding_site.id) + ", " + string(self.location.x) + ", " + string(self.location.y) + ")";
			if cnt < nb {
				query_mosquitoes <- query_mosquitoes + ", ";
			} else {
				query_mosquitoes <- query_mosquitoes + "; ";
			}
			cnt <- cnt + 1;
		}
		
		// --------------------------------- People ---------------------------------	
		string query_people <- "INSERT INTO people(execution_id, simulation_id, cycle, 
			started_from_cycle, name, id, date_of_birth, objective, speed, state, living_place,
			working_place, start_work_h, end_work_h, x, y) VALUES";
		
		cnt <- 1;
		nb <- length(People);
		write "Save States: " + prefix;
		
		
		ask People {
			query_people <- query_people + prefix + ", '" + string(self.name) + "', " + string(self.id) + ", '" + string(starting_date) +
				"', '" + self.objective + "', " + string(self.speed) + ", " + string(self.state) + ", " + string(self.living_place.id) +
				", " + string(self.working_place.id) + ", " + string(self.start_work) + ", " + string(self.end_work) + 
				", " + string(self.location.x) + ", " + string(self.location.y) + ")";
			
			if cnt < nb {
				query_people <- query_people + ", ";
			} else {
				query_people <- query_people + "; ";
			}
			cnt <- cnt + 1;
		}
		
		// --------------------------------- Breeding Sites ---------------------------------	
		string query_bs <- "INSERT INTO breeding_sites(execution_id, simulation_id, cycle, 
			started_from_cycle, name, id, date_of_birth, active, eggs, curr_building, x, y) VALUES";
	
		cnt <- 1;
		nb <- length(BreedingSites);
		
		ask BreedingSites {
			query_bs <- query_bs + prefix + ", '" + string(self.name) + "', " + string(self.id) + ", '" + string(starting_date) +
				"', " + string(self.active) + ", " + string(self.eggs) + ", " + string(self.building_location.id) +
				", " + string(self.location.x) + ", " + string(self.location.y) + ")";
			
			if cnt < nb {
				query_bs <- query_bs + ", ";
			} else {
				query_bs <- query_bs + "; ";
			}
			cnt <- cnt + 1;
		}
		
		// --------------------------------- Mosquitoes ---------------------------------	
		string query_eggs <- "INSERT INTO eggs(execution_id, simulation_id, cycle, 
			started_from_cycle, oviposition_date, breeding_site, deposited_days) VALUES";
	
		cnt <- 1;
		nb <- length(Eggs);
		
		ask Eggs {
			query_eggs <- query_eggs + prefix + ", '" + string(self.deposited_date) +
			"', " + string(self.breeding_site.id) + ", " + string(deposited_days) + ")";
			
			if cnt < nb {
				query_eggs <- query_eggs + ", ";
			} else {
				query_eggs <- query_eggs + "; ";
			}
			cnt <- cnt + 1;
		}
		
		if nb <= 0 {
			query_eggs <- "";
		}
				
		do executeUpdate(
			updateComm: query_mosquitoes + query_people + query_bs + query_eggs
		);
	}
 	
 	reflex save_people_last_cycle when: save_states and run_batch {
 		// --------------------------------- People ---------------------------------	
 		if (!self.isConnected()) {
			do connect (params: POSTGRES);
		}
		
		if run_batch {
			list<string> simulation_id <- simulation_name split_with ' ';
			scenario_id <- int(simulation_id[1]) + 1;
		}
		
		string prefix <- "(" + string(execution_id) + ", " + string(scenario_id) + ", " + string(start_from_cycle + cycle) + ", " + string(start_from_cycle);
		
		string query_people <- "INSERT INTO people(execution_id, simulation_id, cycle, 
			started_from_cycle, name, id, date_of_birth, objective, speed, state, living_place,
			working_place, start_work_h, end_work_h, x, y) VALUES";
		
		int cnt <- 1;
		int nb <- People count ((each.state = 1) and (each.start_infected = false));
		
		write "[SAVE] Saving new " + string(execution_id) + " - " + string(scenario_id) + " - " + string(start_from_cycle + cycle) + " => " + string(nb) + " notifications!";
		
		ask People {
			if self.state = 1 and self.start_infected = false {
				query_people <- query_people + prefix + ", '" + string(self.name) + "', " + string(self.id) + ", '" + string(starting_date) +
					"', '" + self.objective + "', " + string(self.speed) + ", " + string(self.state) + ", " + string(self.living_place.id) +
					", " + string(self.working_place.id) + ", " + string(self.start_work) + ", " + string(self.end_work) + 
					", " + string(self.location.x) + ", " + string(self.location.y) + ")";
				
				if cnt < nb {
					query_people <- query_people + ", ";
				} else {
					query_people <- query_people + "; ";
				}
				cnt <- cnt + 1;
			}
		}
		
		if (cnt > 1) {
			do executeUpdate(
				updateComm: query_people
			);
		}
 	}
 	
	reflex save when: save_states and !end_simulation and ((use_initial_scenario and cycle > 0) or (!use_initial_scenario and cycle >= 0)) {
//		do save_species;
   }
   
   reflex save_metrics when: !end_simulation {	
		if run_batch {
			list<string> simulation_id <- simulation_name split_with ' ';
			scenario_id <- int(simulation_id[1]) + 1;
		}
		
//		write "Saving on Execution: " + string(execution_id) + " - " + string(scenario_id) + " - " + string(cycle);
	
//		do insert(
//			into: "metrics",
//			values: [
//				execution_id, scenario_id, start_from_cycle + cycle,
//				start_from_cycle, string(current_date), "people", 0, cycle_exposed_people[start_from_cycle + cycle],
//				cycle_infected_people[start_from_cycle + cycle], cycle_recovered_people[start_from_cycle + cycle], 0
//		]);
	}
}

// ----------------------------------------------------------
// ---------------------- Experiments -----------------------
// ----------------------------------------------------------asdasdasd
experiment dengue_propagation type: gui until: (cycle >= max_cycles and end_simulation) {
	//
	parameter "Type of execution" var: run_batch category: "bool" init: false;
	parameter "SQLite" var: sqlite_ds category: "string";
	parameter "Start Date" var: start_date_str category: "string" init: "2017-01-09";
	parameter "Max cycles" var: max_cycles category: "int" init: 60;
	parameter "Execution id" var: execution_id category: "int" init: 1;
	parameter "Shapefile:" var: default_shp_dir category: "string" init: "/home/araujo/Documents/dengue-arp-simulation/includes/LIMOEIRO_2500";
	//
	parameter "Number of outbreak agents" var: nb_breeding_sites category: "int";
	parameter "Number of people agents" var: nb_people category: "int";
	parameter "Number of infected people agents" var: nb_infected_people category: "int";
	parameter "Number of mosquitoes agents" var: nb_mosquitoes category: "int";
	parameter "Number of infected mosquitoes agents" var: nb_infected_mosquitoes category: "int";
	//
	parameter "Mosquitoes move probability" var: mosquitoes_move_probability category: "float" init: 0.5;
	parameter "Maximum radius" var: max_move_radius category: "int" init: 100 #m;
	//
	parameter "Start from data" var: use_initial_scenario category: "bool" init: true;
	parameter "Execution number" var: start_from_execution_id category: "int" init: 1;
	parameter "Scenario number" var: start_from_scenario category: "int" init: 0;
	parameter "Cycle number" var: start_from_cycle category: "int" init: 0;
	parameter "Save" var: save_states category: "bool" init: false;
	
	output {
//		display Charts refresh: cycle < 60 axes: true {		
//			chart "Humans" type: series background: #white position: {0,0} style: exploded x_label: "Days" {
//				data "Infected" value: People count (each.state = 1) color: #red;
//				data "Recovered" value: People count (each.state = 2) color: #green;
//			}
//		}
		display city type: opengl{
//			species Buildings aspect: default;
			species Roads aspect: default ;
			species People aspect: default ;
			species Mosquitoes aspect: default ;
//			species BreedingSites aspect: default ;
		}
	}
}


experiment headless_dengue_propagation type: batch keep_seed: true until: (cycle >= max_cycles or end_simulation) repeat: 50 {
	//
	parameter "Type of execution" var: run_batch category: "bool" init: true;
	parameter "SQLite" var: sqlite_ds category: "string";
	parameter "Start Date" var: start_date_str category: "string" init: "2020-05-08";
	parameter "Max cycles" var: max_cycles category: "int" init: 1;
	parameter "Execution id" var: execution_id category: "int" init: 1;
	parameter "Shapefile:" var: default_shp_dir category: "string" init: "/home/araujo/Documents/dengue-arp-simulation/includes/ALTO SANTO_700";
	//
	parameter "Number of outbreak agents" var: nb_breeding_sites category: "int";
	parameter "Number of people agents" var: nb_people category: "int";
	parameter "Number of infected people agents" var: nb_infected_people category: "int";
	parameter "Number of mosquitoes agents" var: nb_mosquitoes category: "int";
	parameter "Number of infected mosquitoes agents" var: nb_infected_mosquitoes category: "int";
	//
	parameter "Mosquitoes move probability" var: mosquitoes_move_probability category: "float" init: 0.5;
	parameter "Maximum radius" var: max_move_radius category: "int" init: 100 #m;
	//
	parameter "Start from data" var: use_initial_scenario category: "bool" init: true;
	parameter "Execution number" var: start_from_execution_id category: "int" init: 1;
	parameter "Scenario number" var: start_from_scenario category: "int" init: 1;
	parameter "Cycle number" var: start_from_cycle category: "int" init: 0;
	parameter "Save" var: save_states category: "bool" init: false;
	
}

