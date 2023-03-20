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
	// Step size
	float step <- 12 #h;
	// Simulation start date
	date start_date <- date("2023-01-01, 05:00 AM", "yyyy-MM-dd, hh:mm a");
	// Max number of cycles
	int max_cycles <- 7;
	// Cycle to start execution
	int cycle_id <- -1 update: cycle_id + 1;
	// Scenario
	int scenario_id <- 1;
	// Start the simulation with the data modified by an external algorithm
	bool start_from_alg <- false;
	// Auxiliar variable to instance generation
	bool save_only_start_end <- true;
	// Map network
	graph road_network;
	// Load data from old simulation
	bool start_from_old_simulation <- false;
	// Number of saves
	int nb_saves <- 2;
	// Current save
	int curr_save <- 0;
	
	// ----------------------------------------------------------------
	// Save pattern
	// 0 - save cycles.
	// 1 - save days.
	// 2 - save days waiting algorithms.
	// 3 - save one day per week.
	// 4 - save one day per week waiting algorithms.
	// ----------------------------------------------------------------
	int application_pattern <- 1;
		
	// Default number of species
	int nb_people <- 10;
	int nb_breeding_sites <- 3;
	int nb_mosquitoes <- 20;
	int nb_infected_people <- 10;
	int nb_infected_mosquitoes <- 20;
	
	// Counter of species
	int cnt_people <- 0;
	int cnt_breeding_sites <- 0;
	int cnt_mosquitoes <- 0;
	
	// ----------------------------------------------------------
	// ------------------ Default Directories -------------------
	// ----------------------------------------------------------
	string default_simulation_data <- "../external/simulation_1/";
	string default_species_dir <- "../external/simulation_1/cycle_1/scenario_1/species_data";
	string default_next_species_dir <- "../external/simulation_1/cycle_1/scenario_1/species_data";
	string default_routes_dir <- "../external/simulation_1/cycle_1/scenario_1/route";
	string default_species_alg_dir <- "../external/simulation_1/cycle_1/scenario_1/species_data_after_alg";
	string default_shp_dir <- "../includes";
	
	// ----------------------------------------------------------
	// ----------------------- Map data -------------------------
	// ----------------------------------------------------------
	// Filename of buildings and roads
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
	float people_min_speed <- 10.0 #km / #h;
	float people_max_speed <- 40.0 #km / #h;
	
	// Recovery rate
	float people_daily_recovery_rate <- 0.143;
	
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
	float mosquitoes_oviposition_rate <- 0.2;
	// Movement
	float mosquitoes_move_probability <- 0.5;
	
	// Oviposition capacity
	int mosquitoes_max_carrying_capacity <- 3;
	// Max move distance
	float max_move_radius <- 50.0 #m;
	
	// ----------------------------------------------------------
	// ------------- Breeding site global parameters ------------
	// ----------------------------------------------------------
		
	// Breeding Sites global parameters
	float bs_eggs_to_mosquitoes <- 0.125;
	float bs_aquatic_phase_mortality_rate <- 0.066;
	
	// ----------------------------------------------------------
	// --------------- Logistics global parameters --------------
	// ----------------------------------------------------------
	float mosquito_insecticide_efficiency <- 0.7;
	float bs_insecticide_efficiency <- 0.1;
	
	// Stop condition
	reflex stop_simulation when: cycle_id >= max_cycles {
		do pause;
	}
	
	// ----------------------------------------------------------
	// ---------------------- Global action ---------------------
	// ----------------------------------------------------------
	// Load actions
	action load_breeding_sites(csv_file bs_data){
		loop breeding_site over: bs_data {
			list<string> line <- string(breeding_site) split_with ',';
			nb_breeding_sites <- nb_breeding_sites + 1;
	
			create BreedingSites {
				// Mandatory information
				name <- line[0];
				id <- int(line[1]);
				// Active
				active <- bool(line[2]);
				// initial state
				eggs <- int(line[3]);
				// current edge
				building_location <- one_of(Buildings where (each.id = int(line[4])));
				// Current location
				location <- point(float(line[5]), float(line[6]));
				// Roads
				buildings <- Buildings at_distance(max_move_radius);
			}
		}
		cnt_breeding_sites <- nb_breeding_sites ;
	}
	
	action load_mosquitoes(csv_file mosquitoes_data){
		cnt_mosquitoes <- 0;
		loop mosquito over: mosquitoes_data {
			list<string> line <- string(mosquito) split_with ',';
			int id_mosquito <- int(line[1]);
			
			if id_mosquito > cnt_mosquitoes {
				cnt_mosquitoes <- id_mosquito + 1;
			}
			
			if line[2] = "2" {
				nb_infected_mosquitoes <- nb_infected_mosquitoes + 1;
			} else {
				nb_mosquitoes <- nb_mosquitoes + 1;
			}
						
			create Mosquitoes {
				// Mandatory information
				name <- line[0];
				id <- id_mosquito;
				// Speed
				speed <- float(line[2]);
				// initial state
				state <- int(line[3]);
				// current edge
				current_building <- one_of(Buildings where (each.id = int(line[4])));
				// Working place
				breeding_site <- one_of(BreedingSites where (each.id = int(line[5])));
				// Current location
				location <- point(float(line[6]), float(line[7]));
			}
		}
	}
	
	action load_people(csv_file people_data) {
		loop person over: people_data {
			list<string> line <- string(person) split_with ',';
			
			if line[4] = "1" {
				nb_infected_people <- nb_infected_people + 1;
			} else {
				nb_people <- nb_people + 1;	
			}
			
			create People {
				// Mandatory information
				name <- line[0];
				id <- int(line[1]);
				objective <- line[2];
				// Speed
				speed <- float(line[3]);
				// initial state
				state <- int(line[4]);
				// Living place
				living_place<- one_of(Buildings where (each.id = int(line[5])));
				// Working place
				working_place<- one_of(Buildings where (each.id = int(line[6])));
				// Set work hours
				start_work <- int(line[7]);
				end_work <- int(line[8]);
				// Current location
				location <- point(float(line[9]), float(line[10]));
			}
		}
		cnt_people <- nb_people + nb_infected_people;
	}
	
	action load_eggs(csv_file eggs_data) {
		loop eggs over: eggs_data {
			list<string> line <- string(eggs) split_with ',';
	
			create Eggs {
				// Mandatory information
				breeding_site <- one_of(BreedingSites where (each.id = int(line[0])));
				deposited_days <- float(line[1]);
			}
		}
	}
	
	action create_street_blocks_and_save {
		// Create blocks
		// Get the number of blocks
		int num_blocks <- Roads max_of(each.block_id);
		
		loop i from: 1 to: num_blocks {
			// Get the roads and vertices of the block
			list<Roads> block_roads <- Roads where (each.block_id = i);
			list nodes <- block_roads collect([each.source_node, each.target_node]);
			list sequence <- [nodes[0][1]];
			
			// Get the right sequence of arcs (streets) 
			bool has_change <- true;
			loop while: length(sequence) < length(nodes) and has_change {
				has_change <- false;
				loop j from: 1 to: length(nodes)-1 {
					if(nodes[j][0].name = sequence[length(sequence)-1].name) {
						add nodes[j][1] to: sequence;
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
	}
	
	// ----------------------------------------------------------
	// ----------------------- Init Model -----------------------
	// ----------------------------------------------------------
	init {
		// End the simulation if no map was provided
		if !file_exists(node_filename) or !file_exists(road_filename) {
			do die;
		}
						
		// Load the roads
		create Roads from: road_shapefile with: [osmid::string(read("osmid")), id::int(read("id_key")), block_id::int(read("block"))];
		
		// Vertex
		create Vertices from: node_shapefile;
		
		// Define the network graph
		road_network <- as_driving_graph(Roads, Vertices);
		
		// Get the path to the start data
		string mosquitoes_filename <- default_species_dir + "/mosquitoes.csv";
		string breeding_sites_filename <- default_species_dir + "/breeding_sites.csv";
		string people_filename <- default_species_dir + "/people.csv";
		string eggs_filename <- default_species_dir + "/eggs.csv";
		
		// If is to continue from a simulation
		if start_from_old_simulation {
			// Overwrite default directories
			if(start_from_alg) {
				mosquitoes_filename <- default_species_alg_dir + "/mosquitoes.csv";
				breeding_sites_filename <- default_species_alg_dir + "/breeding_sites.csv";
				eggs_filename <- default_species_alg_dir + "/eggs.csv";
			}
			
			if file_exists(people_filename) and file_exists(mosquitoes_filename) and file_exists(breeding_sites_filename) and file_exists(eggs_filename) {
				// Open the CSV files
				csv_file breeding_sites_data <- csv_file(breeding_sites_filename, ";", true);
				csv_file mosquitoes_data <- csv_file(mosquitoes_filename, ";", true);
				csv_file people_data <- csv_file(people_filename, ";", true);
				csv_file eggs_data <- csv_file(eggs_filename, ";", true);
				
				// Load the species
				do load_breeding_sites(breeding_sites_data);
				do load_mosquitoes(mosquitoes_data);
				do load_people(people_data);
				do load_eggs(eggs_data);
			} else {
				write "[!] Error to load data!";
				do die;
			}
		} else {
			// Create the default initial folders
			if !folder_exists(default_species_dir) {
				file new_dir <- new_folder(default_species_dir);
				new_dir <- new_folder(default_routes_dir);
				new_dir <- new_folder(default_species_alg_dir);
			}
			
			// Creathe the street blocks that turns into Buildings
			if !file_exists(building_filename) {
				do create_street_blocks_and_save;			
			} else {
				building_shapefile <- file(building_filename);
				create Buildings from: building_shapefile with: [name::read("name"), id::int(read("id")), location::read("location")];
			}
			
			// Create the starting Scenario
			do create_starting_scenario;
		}
		// Specie to save the others
		create Saver{}
	}
}

species Eggs {
	// Breeding site
	BreedingSites breeding_site;
	// Deposited day
	float deposited_days <- 0.0;
	
	reflex turn_mosquito when: every(cycle) {
		deposited_days <- deposited_days + 0.5;
		if flip(min(bs_eggs_to_mosquitoes * deposited_days, 1)) {
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
	// Working parameters
	int start_work;
	int end_work;
	// Current location
	point location;
	// Working and living place
	Buildings living_place;
	Buildings working_place;
	// Target point of the agent
	point target;
	// Speed of the agent
	float speed <- (people_min_speed + rnd(people_max_speed)) #km / #h;
	// (SIR) Current state (susceptible = 0, infected = 1 or recovered = 2)
	int state <- 0;
	
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
		ask Mosquitoes at_distance(5 #m) {
			// Check the mosquitoes state
			if state = 2 and flip(proba){
				myself.state <- 1;
			}
		}
	}
	
	// Reflex to change the state of the agent to recovered
	reflex change_to_recovered_state when: state = 1 and flip(people_daily_recovery_rate) {
		state <- 2;
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
	float speed <- (mosquitoes_min_speed + rnd(mosquitoes_max_speed)) #km / #h;
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
		ask People at_distance(5 #m) {
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
		BreedingSites potential_bs <- BreedingSites at_distance(5 #m) closest_to(self);
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

species Saver {	
	action write_species(bool is_alg_output) {
		default_species_dir <- default_simulation_data + "/cycle_" + string(curr_save) + "/scenario_" + string(scenario_id) + "/species_data/";
		default_routes_dir <- default_simulation_data + "/cycle_" + string(curr_save) + "/scenario_" + string(scenario_id) + "/route/";
		default_species_alg_dir <- default_simulation_data + "/cycle_" + string(curr_save) + "/scenario_" + string(scenario_id) + "/species_data_after_alg/";
		
		// Create directories
		if !folder_exists(default_species_dir) or !folder_exists(default_routes_dir) or !folder_exists(default_species_alg_dir) {
			file new_dir <- new_folder(default_species_dir);
			new_dir <- new_folder(default_routes_dir);
			new_dir <- new_folder(default_species_alg_dir);
		}
		
		string mosquitoes_filename <- default_species_dir + "mosquitoes.csv";
		string people_filename <- default_species_dir + "people.csv";
		string bs_filename <- default_species_dir + "breeding_sites.csv";
		string eggs_filename <- default_species_dir + "eggs.csv";
		
		// Log info
		write "SAVED CYCLE: " + string(cycle) + ", CYCLE_ID: " + string(cycle_id) + ", CURR_SAVE: " + curr_save;
		write "Date: " + start_date plus_hours (12 * cycle_id);
		
		if(is_alg_output = true) {
			mosquitoes_filename <- default_species_alg_dir + "mosquitoes.csv";
			bs_filename <- default_species_alg_dir + "breeding_sites.csv";
			eggs_filename <- default_species_alg_dir + "eggs.csv";
		} else {
			ask People {
				save [name, id, objective, speed, state, living_place.id, working_place.id, start_work, end_work, location.x, location.y]
					to: people_filename type: csv rewrite: (int(self) = 0) ? true : false header: true;
			}
		}
		
		ask BreedingSites {
			save [name, id, active, eggs, building_location.id, location.x, location.y]
				to: bs_filename type: csv rewrite: (int(self) = 0) ? true : false header: true;
		}
		
		ask Mosquitoes {
			save [name, id, speed, state, current_building.id, breeding_site.id, location.x, location.y]
				to: mosquitoes_filename type: csv rewrite: (int(self) = 0) ? true : false header: true;
		}
		
		ask Eggs {
			save [breeding_site.id, deposited_days]
				to: eggs_filename type: csv rewrite: (int(self) = 0) ? true : false header: true;
		}
	}

	csv_file wait_algorithm {
		string routes_filename <- default_routes_dir + "route_" + scenario_id + ".csv";
		loop while: !file_exists(routes_filename) {}
		csv_file routes_csv <- csv_file(routes_filename, ";", true);
		return routes_csv;
	}
	
	action update_species(int id) {
		// Eliminate the Breeding sites	
		ask BreedingSites where (each.building_location.id = id) {
			if flip(bs_insecticide_efficiency) {
				// Kill all the Eggs of this BS
				ask Eggs where (each.breeding_site.id = id) {do die;}
				// Kill de BS
				do die;
			}
		}
		// Eliminate adult mosquitoes
		ask Mosquitoes where (each.current_building.id = id) {
			if flip(mosquito_insecticide_efficiency) {
				do die;
			}
		}
	}
		
	reflex save_patterns_0_1 when: (application_pattern = 0) or ((application_pattern = 1) and (!even(cycle_id) or cycle_id = 0)) {
		if (save_only_start_end and cycle_id in [0, max_cycles]) or !save_only_start_end {
			curr_save <- curr_save + 1;
			do write_species;
		}
	}
	
	reflex save_pattern_2 when: application_pattern = 2 and (!even(cycle_id) or cycle_id = 0) {
		curr_save <- curr_save + 1;
		if(save_only_start_end and cycle_id in [0, max_cycles]) {
			do write_species(is_alg_output: false);
		} else {
			do write_species(is_alg_output: false);
			csv_file csv_routes <- wait_algorithm();
			
			// Apply the insecticide in the blocks
			loop block over: csv_routes {do update_species(id: int(block));}
			
			curr_save <- curr_save + 1;
			do write_species(is_alg_output: true);
		}
	}
	
	// Save patterns: 2, 3, and 4
	reflex save_pattern_3_4 when: (application_pattern in [3, 4]) and cycle_id in [0, 1, 15, 29, 43] and cycle_id <= max_cycles {
		curr_save <- curr_save + 1;
		if(save_only_start_end and cycle_id in [0, max_cycles]) {
			do write_species(is_alg_output: false);
		} else {
			do write_species(is_alg_output: false);
			
			if application_pattern = 4 {
				csv_file csv_routes <- wait_algorithm();
				
				// Apply the insecticide in the blocks
				loop block over: csv_routes {do update_species(id: int(block));}
				
				curr_save <- curr_save + 1;
				do write_species(is_alg_output: true);
			}
		}	 
	}
}

//Species to represent the buildings
species Buildings {
	int id <- -1;
	list<point> road_streets;
	
	aspect default {
		draw shape color: #gray;
	}
}

//Species to represent the roads
species Vertices skills: [skill_road_node] {
	aspect default {
		draw circle(5) color: #black;
	}
}

species Roads skills: [skill_road] {
	// Osmid
	string osmid;
	int id;
	int block_id;
	
	aspect default {
		draw shape color: #black;
	}
}

species Blocks {
	int id <- -1;
	geometry block_polygon;
}

experiment dengue_propagation type: gui {
	parameter "Shapefile for the buildings:" var: building_filename category: "string";
	parameter "Shapefile for the roads:" var: road_filename category: "string";
	parameter "Mosquitoes move probability" var: mosquitoes_move_probability category: "mosquitoes" init: 1.0;
	parameter "Maximum radius" var: max_move_radius category: "mosquitoes" init: 50 #m;
		
	output {
		display city type: opengl{
			species Roads aspect: default ;
			species People aspect: default ;
			species Mosquitoes aspect: default ;
			species BreedingSites aspect: default ;
		}

//		display Charts refresh: cycle < 60 axes: true {
//			chart "Mosquitoes" type: series background: #white position: {0,0} style: exploded x_label: "Days" {
//				data "Susceptible" value: mosquitoes count (each.state = 0) color: #green;
//				data "Exposed" value: mosquitoes count (each.state = 1) color: #yellow;
//				data "Infected" value: mosquitoes count (each.state = 2) color: #red;	
//			}
			
//			chart "Humans" type: series background: #white position: {0,0} style: exploded x_label: "Days" {
//				data "Susceptible" value: people count (each.state = 0) color: #yellow;
//				data "Infected" value: people count (each.state = 1) color: #red;
//				data "Recovered" value: people count (each.state = 2) color: #green;
//			}
//		}
	}
}

experiment headless_dengue_propagation type: batch until: cycle = max_cycles repeat: 1 {
	parameter "Shapefile for the buildings" var: building_filename category: "string";
	parameter "Shapefile for the roads" var: road_filename category: "string";
	parameter "Current cycle id" var: cycle_id category: "int" init: 0;
	parameter "Scenario id" var: scenario_id category: "int" init: 1;
	parameter "Start simulation from algorithm scenario" var: start_from_alg category: "bool" init: false;
	parameter "Number of outbreak agents" var: nb_breeding_sites category: "outbreak" init: 5;
	parameter "Number of people agents" var: nb_people category: "human" init: 10;
	parameter "Number of infected people agents" var: nb_infected_people category: "human" init: 10;
	parameter "Number of mosquitoes agents" var: nb_mosquitoes category: "mosquitoes" init: 20;
	parameter "Number of infected mosquitoes agents" var: nb_infected_mosquitoes category: "mosquitoes" init: 20;
	parameter "Mosquitoes move probability" var: mosquitoes_move_probability category: "mosquitoes" init: 0.5;
	parameter "Maximum radius" var: max_move_radius category: "mosquitoes" init: 200 #m;
	parameter "Base simulation output dir" var: default_simulation_data category: "string" init: "/home/carlos/Documents/phd/code/dengue-arp-tool/temp/simulation_0";
	parameter "Species output dir" var: default_species_dir category: "string" init: "/home/carlos/Documents/phd/code/dengue-arp-tool/temp/simulation_0/cycle_0/scenario_0/species_data";
	parameter "Next species output dir" var: default_next_species_dir category: "string" init: "/home/carlos/Documents/phd/code/dengue-arp-tool/temp/simulation_0/cycle_0/scenario_1/species_data";
	parameter "Routes dir" var: default_routes_dir category: "string" init: "/home/carlos/Documents/phd/code/dengue-arp-tool/temp/simulation_0/cycle_0/scenario_1/route";
	parameter "Species after algorithm output dir" var: default_species_alg_dir category: "string" init: "/home/carlos/Documents/phd/code/dengue-arp-tool/temp/simulation_0/cycle_0/scenario_1/species_data_after_alg";
	parameter "Insecticide efficiency on mosquitoes" var: mosquito_insecticide_efficiency category: "saver" init: 0.7;
	parameter "Insecticide efficiency on breeding sites" var: bs_insecticide_efficiency category: "saver" init: 0.0;
	parameter "Maximum number of cycles" var: max_cycles category: "int" init: 8;
	parameter "Pattern to save the cycles" var: application_pattern category: "saver" init: 1;
	parameter "Save only the final result" var: save_only_start_end category: "saver" init: true;
}

