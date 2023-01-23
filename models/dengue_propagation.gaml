/**
* Name: Dengue Scenario Simulation
* Author: Carlos Araújo
* Description:
* Tags: gis, shapefile, graph, skill, transport
*/

model DenguePropagation

global {
	// ----------------------------------------------------------
	// ----------------------- Map data -------------------------
	// ----------------------------------------------------------
	// Filename of buildings and roads
	string building_filename <- "/home/carlos/Documents/phd/code/dengue-arp-tool/temp/shp/as/nodes.shp";
	string road_filename <- "/home/carlos/Documents/phd/code/dengue-arp-tool/temp/shp/as/edges.shp";
	
	//Shapefile of the roads 
	file road_shapefile <- file(road_filename);
	//Shapefile of the buildings
	file building_shapefile <- file(building_filename);
	//Shape of the environment
	geometry shape <- envelope(road_shapefile);
	
	// ----------------------------------------------------------
	// ------------------- Simulation Config --------------------
	// ----------------------------------------------------------
	// Step size
	float step <- 12 #h;
	// Simulation start date
	date start_date <- date("2023-01-01-05-00-00");
	// Max number of cycles
	int max_cycles <- 8;
	// Cycle to start execution
	int cycle_id <- -1 update: cycle_id + 1;
	// Scenario
	int scenario_id <- 1;
	// Start the simulation with the data modified by an external algorithm
	bool start_from_alg <- false;
		
	// Default number of species
	int nb_people <- 30;
	int nb_outbreaks <- 5;
	int nb_mosquitoes <- 10;
	int nb_infected_people <- 20;
	int nb_infected_mosquitoes <- 10;
	
	// Counter variables
	int cnt_people <- 0;
	int cnt_outbreaks <- 0;
	int cnt_mosquitoes <- 0;
	
	// ----------------------------------------------------------
	// ------------------ Default Directories -------------------
	// ----------------------------------------------------------
	string default_simulation_data <- "/home/carlos/Documents/phd/code/dengue-arp-tool/temp/simulation_0/";
	string deafult_species_dir <- "/home/carlos/Documents/phd/code/dengue-arp-tool/temp/simulation_0/cycle_0/scenario_0/species_data/";
	string default_next_species_dir <- "/home/carlos/Documents/phd/code/dengue-arp-tool/temp/simulation_0/cycle_0/scenario_0/species_data/";
	string default_routes_dir <- "/home/carlos/Documents/phd/code/dengue-arp-tool/temp/simulation_0/cycle_0/scenario_0/route/";
	string deafult_species_alg_dir <- "/home/carlos/Documents/phd/code/dengue-arp-tool/temp/simulation_0/cycle_0/scenario_0/species_data_after_alg/";
	
	// ----------------------------------------------------------
	// ---------------- People global parameters ----------------
	// ----------------------------------------------------------
	// Start-end work time
	int min_work_start <- 6;
	int max_work_start <- 8;
	int min_work_end <- 16;
	int max_work_end <- 20;
	
	// Range speed
	float people_min_speed <- 5.0 #km / #h;
	float people_max_speed <- 40.0 #km / #h;
	
	// Probabilities
	float poeple_daily_recovery_rate <- 0.143;
	
	// ----------------------------------------------------------
	// -------------- Mosquitoes global parameters --------------
	// ----------------------------------------------------------	
	// Range speed
	float mosquitoes_min_speed <- 1.0 #km / #h;
	float mosquitoes_max_speed <- 10.0 #km / #h;
	
	// Probabilities
	float mosquitoes_daily_rate_of_bites <- 0.168;
	float mosquitoes_frac_infectious_bites <- 0.6;
	float mosquitoes_daily_latency_rate	<- 0.143;
	float mosquitoes_susceptibility_to_dengue <- 0.526;
	float mosquitoes_death_rate <- 0.01;
	float mosquitoes_oviposition_rate <- 0.2;
	int mosquitoes_max_carrying_capacity <- 3;
	
	// Prabability of move
	float mosquitoes_move_probability <- 0.5;
	
	// Default move radius
	float max_move_radius <- 150.0 #m;
		
	// Outbreaks global parameters
	float eggs_to_mosquitoes <- 0.125;
	float aquatic_phase_mortality_rate <- 0.06;
	
	// Aux list
	list<road> outbreak_roads;
	
	// ----------------------------------------------------------
	// ----------------- Route global parameters ----------------
	// ----------------------------------------------------------
	float insecticide_efficiency_mosquito <- 0.7;
	float insecticide_efficiency_outbreak <- 0.1;
	int application_pattern <- 0;
	
	reflex stop_simulation when: cycle_id >= max_cycles {
		do pause;
	}
	
	init {
		// End the simulation if no map was provided
		if !file_exists(building_filename) or !file_exists(road_filename) {
			do die;
		}
		
		//Initialization of the building using the shapefile of buildings
		create building from: building_shapefile;
				
		//Initialization of the road using the shapefile of roads
		create road from: road_shapefile with: [osmid::string(read("osmid")), id_key::int(read("id_key"))];
		
		// Get the path to the start data
		string mosquitoes_filename <- deafult_species_dir + "mosquitoes.csv";
		string outbreaks_filename <- deafult_species_dir + "outbreaks.csv";
		string people_filename <- deafult_species_dir + "people.csv";
		
		// If is to continue from a simulation
		if cycle_id != -1 {
			// Overwrite by the algorithm data
			if(start_from_alg) {
				mosquitoes_filename <- deafult_species_alg_dir + "mosquitoes.csv";
				outbreaks_filename <- deafult_species_alg_dir + "outbreaks.csv";
			}
			
			write "---------------";
			write cycle_id;
			write "---------------";

			if file_exists(people_filename) and file_exists(mosquitoes_filename) and file_exists(outbreaks_filename) {
				// Open the CSV files
				csv_file outbreaks_data <- csv_file(outbreaks_filename, ";", true);
				csv_file mosquitoes_data <- csv_file(mosquitoes_filename, ";", true);
				csv_file people_data <- csv_file(people_filename, ";", true);
				
				// Create the species
				// Outbreaks
				loop outbreak over: outbreaks_data {
					list<string> line <- string(outbreak) split_with ',';
					nb_outbreaks <- nb_outbreaks + 1;
					
					create outbreaks {
						// Mandatory informations
						name <- line[0];
						id <- int(line[1]);
						// Active
						active <- bool(line[2]);
						// initial state
						eggs <- int(line[3]);
						// current edge
						road_location <- one_of(road where (each.id_key = int(line[4])));
						// Current location
						location <- point(float(line[5]), float(line[6]));
						// Roads
						start_outbreak_roads <- road at_distance(max_move_radius);
					}
				}
				cnt_outbreaks <- nb_outbreaks;
				
				// Write CSV
				ask outbreaks {
					save [name, id, active, eggs, road_location.id_key, location.x, location.y, length(start_outbreak_roads)]
						to: default_next_species_dir + "outbreaks.csv" type: csv rewrite: (int(self) = 0) ? true : false header: true;
				}
			
				// Mosquitoes
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
					
					create mosquitoes {
						// Mandatory informations
						name <- line[0];
						id <- id_mosquito;
						// Speed
						speed <- float(line[2]);
						// initial state
						state <- int(line[3]);
						// current edge
						current_road <- one_of(road where (each.id_key = int(line[4])));
						// Working place
						start_outbreak <- one_of(outbreaks where (each.id = int(line[5])));
						// Current location
						location <- point(float(line[6]), float(line[7]));
						// Set work hours
						bounds <- circle(max_move_radius, start_outbreak.location);
						// Define the road bounds
						road_bounds <- start_outbreak.start_outbreak_roads;
					}
				}
				
				// Write CSV
				ask mosquitoes {
					save [name, id, speed, state, current_road.id_key, start_outbreak.id, location.x, location.y]
						to: default_next_species_dir + "mosquitoes.csv" type: csv rewrite: (int(self) = 0) ? true : false header: true;
				}
				
				// People
				loop human over: people_data {
					list<string> line <- string(human) split_with ',';
					if line[4] = "1" {
						nb_infected_people <- nb_infected_people + 1;
					} else {
						nb_people <- nb_people + 1;	
					}
					
					create people {
						// Mandatory informations
						name <- line[0];
						id <- int(line[1]);
						objective <- line[2];
						// Speed
						speed<- float(line[3]);
						// initial state
						state<- int(line[4]);
						// Living place
						living_place<- one_of(road where (each.id_key = int(line[5])));
						// Working place
						working_place<- one_of(road where (each.id_key = int(line[6])));
						// Set work hours
						start_work <- int(line[7]);
						end_work <- int(line[8]);
						// Current location
						location <- point(float(line[9]), float(line[10]));
					}
				}
				cnt_people <- nb_people + nb_infected_people;
				//
				ask people {
					save [name, id, objective, speed, state, living_place.id_key, working_place.id_key, start_work, end_work, location.x, location.y]
						to: default_next_species_dir + "people.csv" type: csv rewrite: (int(self) = 0) ? true : false header: true;
				}
			} else {
				do die;
			}
		} else {		
			// Create the default initial folders
			if !folder_exists(deafult_species_dir) {
				file new_dir <- new_folder(deafult_species_dir);
				new_dir <- new_folder(default_routes_dir);
				new_dir <- new_folder(deafult_species_alg_dir);
			}
						
			// Create outbreaks
			outbreak_roads <- nb_outbreaks among road;
			create outbreaks number: nb_outbreaks {
				road_location <- one_of(outbreak_roads);
				location <- any_location_in(road_location);
				start_outbreak_roads <- road at_distance(max_move_radius);
				eggs <- rnd(0, 1) * mosquitoes_max_carrying_capacity;
			}
			
			// Create mosquitoes
			// Infected
			create mosquitoes number: nb_infected_mosquitoes {
				start_outbreak <- one_of(outbreaks);
				bounds <- circle(max_move_radius, start_outbreak.location);
				road_bounds <- start_outbreak.start_outbreak_roads;
				current_road <- one_of(start_outbreak.start_outbreak_roads);
				location <- any_location_in(current_road);
				state <- 2;
			}
			// Susceptible
			create mosquitoes number: nb_mosquitoes {
				start_outbreak <- one_of(outbreaks);
				bounds <- circle(max_move_radius, start_outbreak.location);
				road_bounds <- start_outbreak.start_outbreak_roads;
				current_road <- one_of(start_outbreak.start_outbreak_roads);
				location <- any_location_in(current_road);
				state <- 0;
			}

			// Create people
			// Infected			
			create people number: nb_infected_people {
				living_place <- one_of(road);
				working_place <- one_of(road);
				location <- any_location_in(living_place);
				start_work <- rnd(min_work_start, max_work_start);
				end_work <- rnd(min_work_end, max_work_end);
				state <- 1;
			}
			// Susceptible
			create people number: nb_people {
				living_place <- one_of(road);
				working_place <- one_of(road);
				location <- any_location_in(living_place);
				start_work <- rnd(min_work_start, max_work_start);
				end_work <- rnd(min_work_end, max_work_end);
				state <- 0;
			}
		}
		create saver number: 1 {}
	}
}

// Species to represent the outbreaks points
species outbreaks {
	// Id
	int id <- -1;
	// Outbreak center
	point location;
	// This outbreak focus has eggs
	bool active <- true;
	// Number of eggs
	int eggs <- 0;
	// Road
	road road_location;
	// Possible infested roads
	list<road> start_outbreak_roads;
	
	init {
		if id = -1 {
			id <- cnt_outbreaks;
			cnt_outbreaks <- cnt_outbreaks + 1;
		}
	}
		
	reflex adult_offspring when: every(1 #cycles) and active = true {
		if eggs > 0 {
			int num_new_mosquitoes <- round(eggs_to_mosquitoes * eggs);
			eggs <- eggs - num_new_mosquitoes;
			
			create mosquitoes number: num_new_mosquitoes {
				start_outbreak <- myself;
				bounds <- circle(max_move_radius, start_outbreak.location);
				road_bounds <- start_outbreak.start_outbreak_roads;
				current_road <- one_of(start_outbreak.start_outbreak_roads);
				location <- any_location_in(current_road);
				state <- 0;
			}
		}
	}
	
	reflex aquatic_phase_death when: every(1 #cycles) and active = true {
		if eggs > 0 {
			int aquatic_elimination <- round(aquatic_phase_mortality_rate * eggs);
			eggs <- eggs - aquatic_elimination;
		} 
	}
	
	aspect default {
		draw circle(30) color: #black;
	}		
}

// Species to represent the people using the skill moving
species people skills: [moving]{
	// id
	int id <- -1;
	// Objective (resting or working)
	string objective <- "resting";
	// Working parameters
	int start_work;
	int end_work;
	// Curent location
	point location;
	// Working and living place
	road living_place;
	road working_place;
	// Target point of the agent
	point target;
	// Speed of the agent
	float speed <- (people_min_speed + rnd(people_max_speed)) #km / #h;
	// Currante state (susceptible = 0, infected = 1 or recovered = 2)
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
		do goto (target: target, on: road, recompute_path: false, return_path: false);
		
		if (location = target) {
			target <- nil;
		}	
	}
	
	// Reflex to change the state of the agent to infected
	reflex change_to_infected_state when: state = 0 {
		float proba <- 1 - (1 - mosquitoes_daily_rate_of_bites * mosquitoes_susceptibility_to_dengue);
		ask mosquitoes at_distance(5 #m) {
			// Check the mosquitoes state
			if state = 2 and flip(proba){
				myself.state <- 1;
			}
		}
	}
	
	// Reflex to change the state of the agent to recovered
	reflex change_to_recovered_state when: state = 1 and flip(poeple_daily_recovery_rate) {
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
species mosquitoes skills: [moving] {
	// Id
	int id <- -1;
	// Default speed of the agent
	float speed <- (mosquitoes_min_speed + rnd(mosquitoes_max_speed)) #km / #h;
	// State of the agent (susceptible = 0, exposed = 1 or infected = 2)
	int state <- 0;
	// Target
	point target;
	// Current location
	point location;
	// Movement bounds
	geometry bounds;
	// Start outbreak location
	outbreaks start_outbreak <- nil;
	// Road bounds
	list<road> road_bounds;
	// Current road
	road current_road;
	
	init {
		if id = -1 {
			id <- cnt_mosquitoes;
			name <- "mosquitoes" + string(cnt_mosquitoes);
			cnt_mosquitoes <- cnt_mosquitoes + 1;
		}
	}

	// Reflex to stay in current location or select a random destination
	reflex random_move	when: (target = nil) and (flip(mosquitoes_move_probability)) {
		current_road <- one_of(road_bounds);
		target <- any_location_in(current_road);
	}
	
	// Reflex to move to the target building
	reflex move when: target != nil {
		//we use the return_path facet to return the path followed
		do goto (target: target, on: road, recompute_path: false, return_path: false);
		
		if (location = target) {
			target <- nil;
		}	
	}
	
	// Reflex to change the state of the agent to exposed
	reflex change_to_exposed_state when: state = 0 {
		float proba <- 1 - (1 - mosquitoes_daily_rate_of_bites * mosquitoes_susceptibility_to_dengue);
		ask people at_distance(5 #m) {
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
	
	reflex die when: every(1 #cycles) and flip(mosquitoes_death_rate) {
		do die;
	}
	
	// Reflex to generate a new offspring
	reflex oviposition when: flip(mosquitoes_oviposition_rate){
		outbreaks selected_outbreak <- outbreaks at_distance(5 #m) closest_to(self);
		if selected_outbreak != nil {
			selected_outbreak.eggs <- selected_outbreak.eggs + rnd(1, mosquitoes_max_carrying_capacity);
			selected_outbreak.active <- true;
		}
	}
	
	aspect default {
		if state <= 1 {
			draw circle(5) color: #black;
		} else if state = 2 {
			draw circle(5) color: #red;
		} else {
			draw circle(5) color: #blue;
		}
	}
}

species saver {
	// 0 - save every cycle without external modification.
	// 1 - save every day without external modification.
	// 2 - save every day with an external modification.
	// 3 - save every first week day
	// 4 - save every first week day with an external modification.
	
	action write_species(bool is_alg_output) {
		deafult_species_dir <- default_simulation_data + "cycle_" + string(cycle_id) + "/scenario_" + string(scenario_id) + "/species_data/";
		
		if !folder_exists(deafult_species_dir) {
			default_routes_dir <- default_simulation_data + "cycle_" + string(cycle_id) + "/scenario_" + string(scenario_id) + "/route/";
			deafult_species_alg_dir <- default_simulation_data + "cycle_" + string(cycle_id) + "/scenario_" + string(scenario_id) + "/species_data_after_alg/";
			
			file new_dir <- new_folder(deafult_species_dir);
			new_dir <- new_folder(default_routes_dir);
			new_dir <- new_folder(deafult_species_alg_dir);
		}
		
		string mosquitoes_filename <- deafult_species_dir + "mosquitoes.csv";
		string outbreaks_filename <- deafult_species_dir + "outbreaks.csv";
		string people_filename <- deafult_species_dir + "people.csv";
		
		write "SAVED: " + mosquitoes_filename + ", CYCLE: " + string(cycle) + ", CYCLE_ID: " + string(cycle_id);
		
		if(is_alg_output) {
			mosquitoes_filename <- deafult_species_alg_dir + "mosquitoes.csv";
			outbreaks_filename <- deafult_species_alg_dir + "outbreaks.csv";
		} else {
			ask people {
				save [name, id, objective, speed, state, living_place.id_key, working_place.id_key, start_work, end_work, location.x, location.y]
					to: people_filename type: csv rewrite: (int(self) = 0) ? true : false header: true;
			}
		}
		
		ask outbreaks {
			save [name, id, active, eggs, road_location.id_key, location.x, location.y, length(start_outbreak_roads)]
				to: outbreaks_filename type: csv rewrite: (int(self) = 0) ? true : false header: true;
		}
		
		ask mosquitoes {
			save [name, id, speed, state, current_road.id_key, start_outbreak.id, location.x, location.y]
				to: mosquitoes_filename type: csv rewrite: (int(self) = 0) ? true : false header: true;
		}
	}
	
	csv_file wait_algorithm {
		string routes_filename <- default_routes_dir + "route_" + scenario_id + ".csv";
		
		loop while: !file_exists(routes_filename) {}
		
		csv_file routes_csv <- csv_file(routes_filename, ";", true);
		
		return routes_csv;
	}
	
	action update_species(int street) {
		list<outbreaks> street_outbreaks <- outbreaks where (each.road_location.id_key = street);
		list<mosquitoes> street_mosquitoes <- mosquitoes where (each.current_road.id_key = street);
	
		ask street_outbreaks {
			if flip(insecticide_efficiency_outbreak) {
				do die;
			}
		}
		
		ask street_mosquitoes {
			if flip(insecticide_efficiency_mosquito) {
				do die;
			}
		}
	}

	reflex save_all_cycles when:
		(
			(application_pattern = 0)
			or
			(application_pattern = 1 and even(cycle_id))
		)
		and cycle_id < max_cycles {
		
		do write_species(is_alg_output: false);
	}
	
	reflex save_days_with_algorithm when:
		(
			(application_pattern = 2 and even(cycle_id)) or
			(application_pattern in [3, 4] and mod(cycle_id, 14) = 0)
		) and
			cycle_id < max_cycles
	{
		
		do write_species(is_alg_output: false);
				
		if(application_pattern in [2, 4]) {                
			csv_file csv_routes <- wait_algorithm();
			 
			loop street over: csv_routes {
				do update_species(street: int(street));
			}
			 
			do write_species(is_alg_output: true);
		}	 
	}
}

//Species to represent the buildings
species building {
	aspect default {
		draw shape color: #gray;
	}
}

//Species to represent the roads
species road {
	// Osmid
	string osmid;
	int id_key;
	
	aspect default {
		draw shape color: #gray;
	} 
}

experiment dengue_propagation type: gui {
	parameter "Shapefile for the buildings:" var: building_filename category: "string";
	parameter "Shapefile for the roads:" var: road_filename category: "string";
	parameter "Mosquitoes move probability" var: mosquitoes_move_probability category: "mosquitoes" init: 0.5;
	parameter "Maximum radius" var: max_move_radius category: "mosquitoes" init: 200 #m;
		
	output {
		display city type: opengl{
			species building aspect: default ;
			species road aspect: default ;
			species people aspect: default ;
			species mosquitoes aspect: default ;
			species outbreaks aspect: default ;
			species saver;
		}

//		display Charts refresh: cycle < 60 axes: true {
//			chart "Mosquitoes" type: series background: #white position: {0,0} style: exploded x_label: "Days" {
//				data "Susceptible" value: mosquitoes count (each.state = 0) color: #green;
//				data "Exposed" value: mosquitoes count (each.state = 1) color: #yellow;
//				data "Infected" value: mosquitoes count (each.state = 2) color: #red;	
//			}
//			
//			chart "Humans" type: series background: #white position: {0,0} style: exploded x_label: "Days" {
//				data "Susceptible" value: people count (each.state = 0) color: #yellow;
//				data "Infected" value: people count (each.state = 1) color: #red;
//				data "Recovered" value: people count (each.state = 2) color: #green;
//			}
//		}
	}
}

experiment headless_dengue_propagation type: batch until: cycle = 30 repeat: 1 {
	parameter "Shapefile for the buildings" var: building_filename category: "string";
	parameter "Shapefile for the roads" var: road_filename category: "string";
	parameter "Current cycle id" var: cycle_id category: "int" init: 14;
	parameter "Scenario id" var: scenario_id category: "int" init: 2;
	parameter "Start simulation from algorithm scenario" var: start_from_alg category: "bool" init: false;
	parameter "Number of outbreak agents" var: nb_outbreaks category: "outbreak" init: 5;
	parameter "Number of people agents" var: nb_people category: "human" init: 10;
	parameter "Number of infected people agents" var: nb_infected_people category: "human" init: 10;
	parameter "Number of mosquitoes agents" var: nb_mosquitoes category: "mosquitoes" init: 20;
	parameter "Number of infected mosquitoes agents" var: nb_infected_mosquitoes category: "mosquitoes" init: 20;
	parameter "Mosquitoes move probability" var: mosquitoes_move_probability category: "mosquitoes" init: 0.5;
	parameter "Maximum radius" var: max_move_radius category: "mosquitoes" init: 200 #m;
	parameter "Base simulation output dir" var: default_simulation_data category: "string" init: "/home/carlos/Documents/phd/code/dengue-arp-tool/temp/simulation_0/";
	parameter "Species output dir" var: deafult_species_dir category: "string" init: "/home/carlos/Documents/phd/code/dengue-arp-tool/temp/simulation_0/cycle_14/scenario_0/species_data/";
	parameter "Next species output dir" var: default_next_species_dir category: "string" init: "/home/carlos/Documents/phd/code/dengue-arp-tool/temp/simulation_0/cycle_14/scenario_2/species_data/";
	parameter "Routes dir" var: default_routes_dir category: "string" init: "/home/carlos/Documents/phd/code/dengue-arp-tool/temp/simulation_0/cycle_14/scenario_2/route/";
	parameter "Species after algorithm output dir" var: deafult_species_alg_dir category: "string" init: "/home/carlos/Documents/phd/code/dengue-arp-tool/temp/simulation_0/cycle_14/scenario_2/species_data_after_alg/";
	parameter "Insecticide efficiency on mosquitoes" var: insecticide_efficiency_mosquito category: "saver" init: 0.7;
	parameter "Insecticide efficiency on outbreaks" var: insecticide_efficiency_outbreak category: "saver" init: 0.0;
	parameter "Maximum number of cycles" var: max_cycles category: "int" init: 30;
	parameter "Pattern to save the cycles" var: application_pattern category: "saver" init: 3;
}

