/**
* Name: Dengue Scenario Simulation
* Author: Carlos Araújo
* Description:
* Tags: gis, shapefile, graph, skill, transport
*/

model DenguePropagation

global {
	// Filename of buildings and roads
	string building_filename <- "../includes/tabuleiro/buildings-tabuleiro.shp";
	string road_filename <- "../includes/tabuleiro/roads-tabuleiro.shp";
			
	//Shapefile of the roads 
	file road_shapefile <- file(road_filename);
	//Shapefile of the buildings
	file building_shapefile <- file(building_filename);
	//Shape of the environment
	geometry shape <- envelope(road_shapefile);

	//Step value
	float step <- 12 #h;
	// CSV default data for the agents
	string mosquitoes_csv_filename <- "mosquitoes.csv";
	string people_csv_filename <- "people.csv";
	string outbreaks_csv_filename <- "outbreaks.csv";
	
	string mosquitoes_csv_filename_output <- "mosquitoes.csv";
	string people_csv_filename_output <- "people.csv";
	string outbreaks_csv_filename_output <- "outbreaks.csv";
	
	// Simulation date
	date start_date <- date("2022-01-01-05-00-00");
	
	// Work movimentation
	int min_work_start <- 6;
	int max_work_start <- 8;
	int min_work_end <- 16;
	int max_work_end <- 20;
	
	// People deafult speed
	float people_min_speed <- 5.0 #km / #h;
	float people_max_speed <- 30.0 #km / #h;
	
	// Mosquitoes deafult speed
	float mosquitoes_min_speed <- 1.0 #km / #h;
	float mosquitoes_max_speed <- 5.0 #km / #h;
	
	// Mosquitoes parameters
	float mosquitoes_daily_rate_of_bites <- 0.168;
	float mosquitoes_frac_infectious_bites <- 0.6;
	float mosquitoes_daily_latency_rate	<- 0.143;
	float mosquitoes_susceptibility_to_dengue <- 0.526;
	float mosquitoes_death_rate <- 0.05;
	
	// Prabability of move
	float mosquitoes_move_probability <- 0.5;
	
	// People parameters
	float poeple_daily_recovery_rate <- 0.0143;
	
	// Outbreaks parameters
	float mosquitoes_oviposition_rate <- 0.2;
	float eggs_to_mosquitoes <- 0.125;
	int mosquitoes_max_carrying_capacity <- 3;
	float aquatic_phase_mortality_rate <- 0.06;
	
	//
	list<road> outbreak_roads;
	int nb_outbreaks <- 5;
	
	// 
	int nb_people <- 5;
	int nb_infected_people <- 0;
	
	//
	int nb_mosquitoes <- 0;
	int nb_infected_mosquitoes <- 3;
	
	//
	float max_move_radius <- 100.0 #m;
	
	//
	list<outbreaks> created_outbreaks;
	
	init {
		if !file_exists(building_filename) or !file_exists(road_filename) {
			do die;
		}
		
		//Initialization of the building using the shapefile of buildings
		create building from: building_shapefile;
				
		//Initialization of the road using the shapefile of roads
		create road from: road_shapefile with: [osmid::string(read("osm_id"))];
		
		// Create the outbreaks species
		if file_exists(outbreaks_csv_filename) {
			csv_file outbreaks_data <- csv_file(outbreaks_csv_filename, ";", true);
		} else {
			outbreak_roads <- nb_outbreaks among road;
			
			create outbreaks number: nb_outbreaks returns: cr_outbreaks {
				road_location <- one_of(outbreak_roads);
				location <- any_location_in(road_location);
				start_outbreak_roads <- road at_distance(max_move_radius);
				eggs <- rnd(1, 10) * mosquitoes_max_carrying_capacity;
			}
			
//			created_outbreaks <- cr_outbreaks;
//			write created_outbreaks;
		}
		
		// Create the mosquitoes speciest
		if file_exists(mosquitoes_csv_filename) {
			csv_file mosquitoes_data <- csv_file(mosquitoes_csv_filename, ";", true);
		} else {
			create mosquitoes number: nb_infected_mosquitoes {
				start_outbreak <- one_of(outbreaks);
				bounds <- circle(max_move_radius, start_outbreak.location);
				road_bounds <- start_outbreak.start_outbreak_roads;
				current_road <- one_of(start_outbreak.start_outbreak_roads);
				location <- any_location_in(current_road);
				state <- 2;
			}
			
			create mosquitoes number: nb_mosquitoes {
				start_outbreak <- one_of(outbreaks);
				bounds <- circle(max_move_radius, start_outbreak.location);
				road_bounds <- start_outbreak.start_outbreak_roads;
				current_road <- one_of(start_outbreak.start_outbreak_roads);
				location <- any_location_in(current_road);
				state <- 0;
			}
			
		}
		
		// Create the people species
		if file_exists(people_csv_filename) {
			csv_file people_data <- csv_file(people_csv_filename, ";", true);
		} else {
			create people number: nb_people {
				living_place <- one_of(road);
				working_place <- one_of(road);
				location <- any_location_in(living_place);
				start_work <- rnd(min_work_start, max_work_start);
				end_work <- rnd(min_work_end, max_work_end);
				state <- 0;
			}
			
			create people number: nb_infected_people {
				living_place <- one_of(road);
				working_place <- one_of(road);
				location <- any_location_in(living_place);
				start_work <- rnd(min_work_start, max_work_start);
				end_work <- rnd(min_work_end, max_work_end);
				state <- 1;
			}
		}
				
		// Creation of the people agents
//		loop human over: people_data {
//			list<string> line <- string(human) split_with ',';
//			
//			create people {
//				// Mandatory informations
//				name <- line[0];
//				id <- int(line[1]);
//				objective <- line[2];
//				// Setting the default values and random if no value was reported
//				// Speed
//				speed<-line[3] = "nil" ? rnd(people_min_speed, people_max_speed) : float(line[3]);
//				// initial state
//				state<-line[4] = "nil" ? 0 : int(line[4]);
//				// Living place
//				living_place<-line[5] = "nil" ? one_of(building) : one_of(building where (each.osmid = line[5]));
//				// Working place
//				working_place<-line[6] = "nil" ? one_of(building) : one_of(building where (each.osmid = line[6]));
//				// Set work hours
//				start_work <- line[7] = "nil" ? rnd(min_work_start, max_work_start) : int(line[7]);
//				end_work <- line[8] = "nil" ? rnd(min_work_end, max_work_end) : int(line[8]);
//				// Current location
//				current_location<-line[10] = "nil" ? any_location_in(living_place) : point(float(line[10]), float(line[11]));
//			}
//		}
		
	}
}

// Species to represent the outbreaks points
species outbreaks {
	// Id
	int id;
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
	int id;
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
	float speed <- (5 + rnd(30)) #km/#h;
	// Currante state (susceptible = 0, infected = 1 or recovered = 2)
	int state <- 0;
	
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
		ask mosquitoes at_distance(15 #m) {
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
			draw circle(20) color: #yellow;	
		} else if state = 1 {
			draw circle(20) color: #red;
		} else {
			draw circle(20) color: #green;
		}	
	}
}

// Species to represent the mosquitoes using the skill moving
species mosquitoes skills: [moving] {
	// Id
	int id;
	// Default speed of the agent
	float speed <- (2 + rnd(5)) #km / #h;
	// State of the agent (susceptible = 0, exposed = 1 or infected = 2)
	int state <- 0;
	// Target
	point target;
	// Movement bounds
	geometry bounds;
	// Start outbreak location
	outbreaks start_outbreak;
	// Road bounds
	list<road> road_bounds;
	// Current road
	road current_road;

	// Reflex to stay in current location or select a random destination
	reflex stay	when: (target = nil) and (flip(mosquitoes_move_probability)) {
		current_road <- one_of(road_bounds);
		if current_road = nil {
			write length(road_bounds);
		}
		target <- any_location_in(current_road);
	}
	
	// Reflex to move
	reflex move when: target != nil {
		do goto (target: target, on: road, recompute_path: false, return_path: false);
		
		if target = location {
			target <- nil;
		}
	}
	
	// Reflex to change the state of the agent to exposed
	reflex change_to_exposed_state when: state = 0 {
		float proba <- 1 - (1 - mosquitoes_daily_rate_of_bites * mosquitoes_susceptibility_to_dengue);
		ask people at_distance(15 #m) {
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
	
//	reflex die when: every(1 #cycles) and flip(mosquitoes_death_rate) {
//		do die;
//	}
	
	// Reflex to generate a new offspring
	reflex oviposition when: flip(mosquitoes_oviposition_rate){
		outbreaks selected_outbreak <- outbreaks at_distance(5 #m) closest_to(self);
		if selected_outbreak != nil {
			selected_outbreak.eggs <- selected_outbreak.eggs + rnd(1, mosquitoes_max_carrying_capacity);
			selected_outbreak.active <- true;
		}
	}
	
	aspect default {
		if state = 0 {
			draw circle(10) color: #red;
		} else if state = 1 {
			draw circle(10) color: #red;
		} else {
			draw circle(10) color: #red;
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
	aspect default {
		draw shape color: #black;
	} 
}

experiment dengue_propagation type: gui {
	parameter "Shapefile for the buildings:" var: building_filename category: "string";
	parameter "Shapefile for the roads:" var: road_filename category: "string";
	parameter "Number of people agents" var: nb_people category: "human" init: 20;
	parameter "Number of infected people agents" var: nb_infected_people category: "human" init: 10;
	parameter "Number of mosquitoes agents" var: nb_mosquitoes category: "mosquitoes" init: 10;
	parameter "Number of infected mosquitoes agents" var: nb_infected_mosquitoes category: "mosquitoes" init: 100;
	parameter "Mosquitoes move probability" var: mosquitoes_move_probability category: "mosquitoes" init: 0.5;
	parameter "Mosquitoes csv file" var: mosquitoes_csv_filename category: "string";
	parameter "People csv file" var: people_csv_filename category: "string";
	parameter "Outbreaks csv file" var: outbreaks_csv_filename category: "string";	
	parameter "Mosquitoes csv output file" var: mosquitoes_csv_filename_output category: "string";
	parameter "People csv output file" var: people_csv_filename_output category: "string";
	parameter "Outbreaks csv output file" var: outbreaks_csv_filename_output category: "string";
	parameter "Maximum radius" var: max_move_radius category: "mosquitoes" init: 100 #m;
	
	output {
		display city type: opengl{
			species building aspect: default ;
			species road aspect: default ;
			species people aspect: default ;
			species mosquitoes aspect: default ;
			species outbreaks aspect: default ;
		}
		display chart refresh: every(1#cycles) axes: false {
			chart "Mosquitoes" type: series background: #white style: exploded {
				data "New" value: mosquitoes count (each.state = 0) color: rgb(204,4,11);
				data "Susceptible" value: mosquitoes count (each.state = 1) color: rgb(46,204,113);
				data "infected" value: mosquitoes count (each.state = 2) color: rgb(231,76,60);	
//				data "New" value: people count (each.state = 0) color: rgb(204,4,11);
//				data "Infected People" value: people count (each.state = 1) color: rgb(52,152,219);
//				data "Recovered People" value: people count (each.state = 2) color: rgb(152,52,29);
			}
		}
	}
}

experiment headless_dengue_propagation type: batch until: cycle = 1 repeat: 1 {
	parameter "Shapefile for the buildings:" var: building_filename category: "string";
	parameter "Shapefile for the roads:" var: road_filename category: "string";
	parameter "Number of people agents" var: nb_people category: "human" init: 20;
	parameter "Number of infected people agents" var: nb_infected_people category: "human" init: 10;
	parameter "Number of mosquitoes agents" var: nb_mosquitoes category: "mosquitoes" init: 20;
	parameter "Number of infected mosquitoes agents" var: nb_infected_mosquitoes category: "mosquitoes" init: 20;
	parameter "Mosquitoes move probability" var: mosquitoes_move_probability category: "mosquitoes" init: 0.5;
	parameter "Mosquitoes csv file" var: mosquitoes_csv_filename category: "string";
	parameter "People csv file" var: people_csv_filename category: "string";
	parameter "Outbreaks csv file" var: outbreaks_csv_filename category: "string";	
	parameter "Mosquitoes csv output file" var: mosquitoes_csv_filename_output <- "mosquitoes_" + 1 + ".csv";
	parameter "People csv output file" var: people_csv_filename_output <- "people_" + 1 + ".csv";
	parameter "Outbreaks csv output file" var: outbreaks_csv_filename_output <- "outbreaks_" + 1 + ".csv";
	parameter "Maximum radius" var: max_move_radius category: "mosquitoes" init: 200 #m;
	
	reflex save_results {
		ask mosquitoes {
//			write [name, current_road];
			save [name, id, speed, state, current_road.osmid, location.x, location.y] to: mosquitoes_csv_filename_output type: csv 
			rewrite: (int(self) = 0) ? true : false header: true;
		}

		ask people {
//			write [name, living_place.osmid, working_place.osmid];
			save [name, id, speed, state, living_place.osmid, working_place.osmid, start_work, end_work, objective, location.x, location.y] to: people_csv_filename_output type: csv
			rewrite: (int(self) = 0) ? true : false header: true;
		}
		
		ask outbreaks {
//			write [name, road_location.osmid];
			save [name, id, active, eggs, road_location.osmid, location.x, location.y] to: outbreaks_csv_filename_output type: csv
			rewrite: (int(self) = 0) ? true : false header: true;
		}
	}
}

