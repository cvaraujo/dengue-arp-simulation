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
	geometry shape <- envelope(shape_file_bounds);
	float step <- 12 #h;
	date starting_date <- date("2022-01-01-00-00-00");
	int nb_people <- 200;
	int nb_people_infected <- 5;
	int nb_mosquitoes <- 20;
	int nb_mosquitoes_infected <- 10;
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
	int nb_hi <- nb_people_infected update: human count (each.state = 1);

	init {
		create building from: shape_file_buildings with: [type:: string(read("landuse"))] {
			if type = "residential" {
				color <- #gray;
			} else {
				color <- #gray;
			}

		}

		create road from: shape_file_roads;
		list<building> residential_buildings <- building where (each.type = "residential");
		list<building> industrial_buildings <- building where (each.type != "residential");
		create human number: nb_people {
			speed <- rnd(min_speed, max_speed);
			start_work <- rnd(min_work_start, max_work_start);
			end_work <- rnd(min_work_end, max_work_end);
			living_place <- one_of(residential_buildings);
			working_place <- one_of(industrial_buildings);
			objective <- "resting";
			location <- any_location_in(living_place);
		}

		create mosquitoes number: nb_mosquitoes {
			speed_msq <- rnd(min_speed, max_speed);
			start_place <- one_of(residential_buildings);
			start_point <- any_location_in(start_place);
		}

		ask nb_people_infected among human {
			state <- 1;
		}

		ask nb_mosquitoes_infected among mosquitoes {
			state_msq <- 1;
		}

	}

}

species road {
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
	rgb color_msq <- #black;
	float speed_msq <- (2 + rnd(5)) #km / #h;
	float dist_of_start <- 100 #m;
	int state_msq <- 0;
	building start_place <- nil;
	point the_target <- nil;
	point start_point <- nil;

	reflex stay when: the_target = nil {
		ask building at_distance dist_of_start {
			if flip(0.5) {
				myself.the_target <- any_location_in(one_of(building));
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

}

// People definition
species human skills: [moving] {
	rgb color <- #yellow;
	float speed <- (5 + rnd(10)) #km / #h;
	int state <- 0;
	building living_place <- nil;
	building working_place <- nil;
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
			if state_msq = 1 and flip(b) { //flip(1 - (1 - a * b)) {
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

experiment DengueARCRouting type: gui {
	parameter "Shapefile for the buildings:" var: shape_file_buildings category: "GIS";
	parameter "Shapefile for the roads:" var: shape_file_roads category: "GIS";
	parameter "Shapefile for the bounds:" var: shape_file_bounds category: "GIS";
	parameter "Number of people agents" var: nb_people category: "human";
	parameter "Earliest hour to start work" var: min_work_start category: "human" min: 2 max: 8;
	parameter "Latest hour to start work" var: max_work_start category: "human" min: 8 max: 12;
	parameter "Earliest hour to end work" var: min_work_end category: "human" min: 12 max: 16;
	parameter "Latest hour to end work" var: max_work_end category: "human" min: 16 max: 23;
	parameter "minimal speed" var: min_speed category: "human" min: 0.1 #km / #h;
	parameter "maximal speed" var: max_speed category: "human" max: 10 #km / #h;
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