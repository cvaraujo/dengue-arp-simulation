/**
* Name: Road simulation
* Author: Carlos Araújo
* Description: 
* Tags: graph
*/
model DengueARCRouting

global {
	file shape_file_buildings <- file("../includes/buildings-limoeiro.shp");
	file shape_file_roads <- file("../includes/routes-limoeiro.shp");
	file shape_file_bounds <- file("../includes/buildings-limoeiro.shp");
	csv_file mosquitoes_data <- csv_file("../output/mosquitoes_1.csv", ";", true);
	csv_file people_data <- csv_file("../output/people_1.csv", ";", true);
	geometry shape <- envelope(shape_file_bounds);
	date starting_date <- date("2022-01-01-00-00-00");
	float step <- 12 #h;
	int nb_people <- 10;
	int nb_people_infected <- 5;
	int nb_mosquitoes <- 10;
	int nb_mosquitoes_infected <- 5;
	int min_work_start <- 6;
	int max_work_start <- 8;
	int min_work_end <- 16;
	int max_work_end <- 20;
	float min_speed <- 1.0 #km / #h;
	float max_speed <- 5.0 #km / #h;
	graph the_graph;
	// Mosquitoes parameters
	float a <- 0.268;
	float b <- 0.8;
	float H <- 0.143;
	float M <- 0.143;
	float c <- 0.526;
	float L <- 0.5;
	float death_rate <- 0.05;
	float dist_of_start <- 150 #m;
	int id_mosquito <- 0;
	int id_human <- 0;
	int nb_hi <- nb_people_infected update: human count (each.state = 1);

	init {
		create building from: shape_file_buildings with: [type:: string(read("landuse"))] {
			color <- #gray;
		}

		create road from: shape_file_roads with: [osmid::string(read("osm_id")), type:: string(read("highway"))] {
			if type = "residential" {
				color <- #black;
			} else {
				color <- #red;
			}

		}

		list<road> residential_buildings <- road where (each.type = "residential");
		list<road> industrial_buildings <- road where (each.type != "residential");
		loop hm over: people_data {
			list<string> h <- string(hm) split_with ',';
			create human {
				name <- h[0];
				id <- int(h[1]);
				objective <- h[9];
				// Set the speed
				if float(h[3]) != -1 {
					speed <- float(h[3]);
				} else {
					speed <- rnd(min_speed, max_speed);
				}
				// initial state
				if int(h[4]) >= 0 {
					state <- int(h[4]);
				} else {
					state <- 0;
				}
				// Set the living place
				if h[5] = "nil " {
					living_place <- one_of(residential_buildings);
				} else {
					living_place <- one_of(road where (each.osmid = h[5]));
				}
				// set working place
				if h[6] = "nil" {
					working_place <- one_of(industrial_buildings);
				} else {
					working_place <- one_of(road where (each.osmid = h[6]));
				}
				// Set start work
				if int(h[7]) = -1 {
					start_work <- rnd(min_work_start, max_work_start);
				} else {
					start_work <- int(h[7]);
				}

				if int(h[8]) = -1 {
					end_work <- rnd(min_work_end, max_work_end);
				} else {
					end_work <- int(h[8]);
				}

				if h[10] = "nil" {
					location <- any_location_in(living_place);
				} else {
					location <- point(float(h[10]), float(h[11]));
				}

			}

		}

		loop md over: mosquitoes_data {
			list<string> h <- string(md) split_with ',';
			create mosquitoes {
				name <- h[0];
				id <- int(h[1]);
				// Set the speed
				if float(h[3]) != -1 {
					speed <- float(h[3]);
				} else {
					speed <- rnd(min_speed, max_speed);
				}
				// initial state
				if int(h[4]) >= 0 {
					state_msq <- int(h[4]);
				} else {
					state_msq <- 0;
				}
				// Set the living place
				if h[5] = "nil" {
					start_place <- one_of(residential_buildings);
				} else {
					start_place <- one_of(road where (each.osmid = h[5]));
				}

				if h[6] = "nil" {
					start_point <- any_location_in(start_place);
				} else {
					start_point <- point(float(h[6]), float(h[7]));
				}
				// Set the living place
				if h[8] = "nil" {
					last_position <- start_place;
				} else {
					last_position <- one_of(road where (each.osmid = h[8]));
				}

				if h[9] = "nil" {
					location <- any_location_in(start_place);
				} else {
					location <- point(float(h[9]), float(h[10]));
				}

			}

		}

		//		create mosquitoes number: nb_mosquitoes {
		//			id <- id_mosquito;
		//			id_mosquito <- id_mosquito + 1;
		//			speed_msq <- rnd(min_speed, max_speed);
		//			start_place <- one_of(residential_buildings);
		//			start_point <- any_location_in(start_place);
		//			last_position <- start_place;
		//		}
		// name, id, color_msq, speed, state_msq, start_place.osmid, start_point.x, start_point.y, last_position.osmid, location.x, location.y
		//		ask nb_people_infected among human {
		//			state <- 1;
		//		}
		//		ask nb_mosquitoes_infected among mosquitoes {
		//			state_msq <- 1;
		//		}

	}

}

species road {
	string osmid;
	string type;
	rgb color <- #black;

	aspect base {
		draw shape color: color;
	}

}

species building {
	string type;
	rgb color <- #gray;

	aspect base {
		draw shape color: color;
	}

}

// Mosquitoes definition
species mosquitoes skills: [moving] {
	int id;
	rgb color_msq <- #black;
	float speed_msq <- (10 + rnd(5)) #km / #h;
	int state_msq <- 0;
	road start_place <- nil;
	point the_target <- nil;
	point start_point <- nil;
	road last_position <- nil;

	reflex stay when: the_target = nil {
		ask road at_distance dist_of_start {
			if flip(0.8) {
				road bg <- one_of(road);
				point target <- any_location_in(bg);
				if target distance_to myself.start_point <= dist_of_start {
					myself.the_target <- target;
					myself.last_position <- bg;
				}

			}

		}

	}

	reflex move when: the_target != nil {
		do goto target: the_target on: the_graph;
		if the_target = location {
			the_target <- nil;
		}

	}

	aspect base {
		if state_msq = 0 {
			draw circle(10) color: #black;
		} else if state_msq = 1 {
			draw circle(10) color: #red;
		} else {
			draw circle(10) color: #black;
		}

	}

	reflex change_to_infected_state when: state_msq = 0 {
		ask human at_distance 20 #m {
			if state = 1 and flip(M) {
				myself.state_msq <- 1;
			}

		}

	}

	reflex change_to_death when: state_msq < 2 {
		if flip(death_rate) {
			do die;
		}

	}

}

// People definition
species human skills: [moving] {
	int id;
	rgb color <- #yellow;
	float speed <- (20 + rnd(30)) #km / #h;
	int state <- 0;
	road living_place <- nil;
	road working_place <- nil;
	int start_work;
	int end_work;
	string objective;
	point the_target <- nil;

	reflex time_to_work when: current_date.hour = start_work and objective = "resting" {
		objective <- "working";
		the_target <- any_location_in(working_place);
	}

	reflex time_to_go_home when: current_date.hour = end_work and objective = "working" {
		objective <- "resting";
		the_target <- any_location_in(living_place);
	}

	reflex move when: the_target != nil {
		path path_followed <- goto(target: the_target, on: the_graph, return_path: true);
		if the_target = location {
			the_target <- nil;
		} }

	reflex change_to_infected_state when: state = 0 {
		ask mosquitoes at_distance 20 #m {
			if state_msq = 1 and flip(b) {
				myself.state <- 1;
			}

		}

	}

	reflex change_to_recovered_state when: state = 1 {
		if flip(H) {
			state <- 2;
		}

	}

	aspect base {
		if state = 0 {
			draw circle(10) color: #yellow;
		} else if state = 1 {
			draw circle(10) color: #green;
		} else {
			draw circle(10) color: #blue;
		}

	} }

experiment explore_model type: batch until: cycle = 2 repeat: 1 {
	parameter "Shapefile for the buildings:" var: shape_file_buildings category: "GIS";
	parameter "Shapefile for the roads:" var: shape_file_roads category: "GIS";
	parameter "Shapefile for the bounds:" var: shape_file_bounds category: "GIS";
	parameter "Number of people agents Min" var: nb_people category: "human" min: 10;
	parameter "Number of people agents Max" var: nb_people category: "human" min: 10;
	parameter "Number of people infected Min" var: nb_people_infected category: "human" min: 5;
	parameter "Number of people infected Max" var: nb_people_infected category: "human" min: 5;
	parameter "Number of Mosquitoes Min" var: nb_mosquitoes category: "mosquitoes" min: 10;
	parameter "Number of Mosquitoes Max" var: nb_mosquitoes category: "mosquitoes" max: 10;
	parameter "Number of Mosquitoes infected Min" var: nb_mosquitoes_infected category: "mosquitoes" min: 5;
	parameter "Number of Mosquitoes infected Max" var: nb_mosquitoes_infected category: "mosquitoes" max: 5;
	parameter "Earliest hour to start work" var: min_work_start category: "human" min: 2 max: 8;
	parameter "Latest hour to start work" var: max_work_start category: "human" min: 8 max: 12;
	parameter "Earliest hour to end work" var: min_work_end category: "human" min: 12 max: 16;
	parameter "Latest hour to end work" var: max_work_end category: "human" min: 16 max: 23;
	parameter "minimal speed" var: min_speed category: "human" min: 0.1 #km / #h;
	parameter "maximal speed" var: max_speed category: "human" max: 10 #km / #h;
	parameter "death rate" var: death_rate category: "mosquitoes" min: 0.05;
	parameter "death rate" var: death_rate category: "mosquitoes" max: 0.1;
	parameter "dist of start" var: dist_of_start category: "mosquitoes" min: 100 #m;
	parameter "dist of start" var: dist_of_start category: "mosquitoes" max: 150 #m;

	reflex save_results {
		ask mosquitoes {
			write [name, start_place, last_position];
			save [name, id, color_msq, speed, state_msq, start_place.osmid, start_point.x, start_point.y, last_position.osmid, location.x, location.y] to: "../output/mosquitoes.csv" type:
			csv rewrite: (int(self) = 0) ? true : false header: true;
		}

		ask human {
			write [name, living_place.osmid, working_place.osmid];
			save [name, id, color, speed, state, living_place.osmid, working_place.osmid, start_work, end_work, objective, location.x, location.y] to: "../output/people.csv" type: csv
			rewrite: (int(self) = 0) ? true : false header: true;
		}

	}

}

experiment DengueARCRouting type: gui {
	parameter "Shapefile for the buildings:" var: shape_file_buildings category: "GIS";
	parameter "Shapefile for the roads:" var: shape_file_roads category: "GIS";
	parameter "Shapefile for the bounds:" var: shape_file_bounds category: "GIS";
	parameter "Number of people agents Min" var: nb_people category: "human" min: 10;
	parameter "Number of people agents Max" var: nb_people category: "human" min: 10;
	parameter "Number of people infected Min" var: nb_people_infected category: "human" min: 5;
	parameter "Number of people infected Max" var: nb_people_infected category: "human" min: 5;
	parameter "Number of Mosquitoes Min" var: nb_mosquitoes category: "mosquitoes" min: 10;
	parameter "Number of Mosquitoes Max" var: nb_mosquitoes category: "mosquitoes" max: 10;
	parameter "Number of Mosquitoes infected Min" var: nb_mosquitoes_infected category: "mosquitoes" min: 5;
	parameter "Number of Mosquitoes infected Max" var: nb_mosquitoes_infected category: "mosquitoes" max: 5;
	parameter "Earliest hour to start work" var: min_work_start category: "human" min: 2 max: 8;
	parameter "Latest hour to start work" var: max_work_start category: "human" min: 8 max: 12;
	parameter "Earliest hour to end work" var: min_work_end category: "human" min: 12 max: 16;
	parameter "Latest hour to end work" var: max_work_end category: "human" min: 16 max: 23;
	parameter "minimal speed" var: min_speed category: "human" min: 0.1 #km / #h;
	parameter "maximal speed" var: max_speed category: "human" max: 10 #km / #h;
	parameter "death rate" var: death_rate category: "mosquitoes" min: 0.05;
	parameter "death rate" var: death_rate category: "mosquitoes" max: 0.1;
	parameter "dist of start" var: dist_of_start category: "mosquitoes" min: 100 #m;
	parameter "dist of start" var: dist_of_start category: "mosquitoes" max: 150 #m;
	output {
		display city_display type: opengl {
			species building aspect: base;
			species human aspect: base;
			species mosquitoes aspect: base;
			species road aspect: base;
		}

		display chart_display refresh: every(1 #cycles) {
			chart "Disease spreading" type: series {
				data "infected" value: nb_hi color: #red;
			}

		}

	}

}