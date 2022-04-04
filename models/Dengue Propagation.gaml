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
	float step <- 10 #mn;
	date starting_date <- date("2022-01-01-00-00-00");
	int nb_people <- 50;
	int min_work_start <- 6;
	int max_work_start <- 8;
	int min_work_end <- 16;
	int max_work_end <- 20;
	float min_speed <- 1.0 #km / #h;
	float max_speed <- 5.0 #km / #h;
	float destroy <- 0.02;
	graph the_graph;

	init {
		create building from: shape_file_buildings with: [type:: string(read("landuse"))] {
			if type = "residential" {
				color <- #blue;
			}

		}

		create road from: shape_file_roads;
		map<road, float> weights_map <- road as_map (each::(each.destruction_coeff * each.shape.perimeter));
		the_graph <- as_edge_graph(road) with_weights weights_map;
		list<building> residential_buildings <- building where (each.type = "residential");
		list<building> industrial_buildings <- building where (each.type != "residential");
		create people number: nb_people {
			speed <- rnd(min_speed, max_speed);
			start_work <- rnd(min_work_start, max_work_start);
			end_work <- rnd(min_work_end, max_work_end);
			living_place <- one_of(residential_buildings);
			working_place <- one_of(industrial_buildings);
			objective <- "resting";
			location <- any_location_in(living_place);
		}

	}

	reflex update_graph {
		map<road, float> weights_map <- road as_map (each::(each.destruction_coeff * each.shape.perimeter));
		the_graph <- the_graph with_weights weights_map;
	}

}

species building {
	string type;
	rgb color <- #gray;

	aspect base {
		draw shape color: color;
	}

}

species road {
	float destruction_coeff <- rnd(1.0, 2.0) max: 2.0;
	int colorValue <- int(255 * (destruction_coeff - 1)) update: int(255 * (destruction_coeff - 1));
	rgb color <- rgb(min([255, colorValue]), max([0, 255 - colorValue]), 0) update: rgb(min([255, colorValue]), max([0, 255 - colorValue]), 0);

	aspect base {
		draw shape color: color;
	}

}

species people skills: [moving] {
	rgb color <- #yellow;
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
		list<geometry> segments <- path_followed.segments;
		loop line over: segments {
			float dist <- line.perimeter;
			ask road(path_followed agent_from_geometry line) {
				destruction_coeff <- destruction_coeff + (destroy * dist / shape.perimeter);
			}

		}

		if the_target = location {
			the_target <- nil;
		} }

	aspect base {
		draw circle(10) color: color border: #black;
	} }

experiment DengueARCRouting type: gui {
	parameter "Shapefile for the buildings:" var: shape_file_buildings category: "GIS";
	parameter "Shapefile for the roads:" var: shape_file_roads category: "GIS";
	parameter "Shapefile for the bounds:" var: shape_file_bounds category: "GIS";
	parameter "Number of people agents" var: nb_people category: "People";
	parameter "Earliest hour to start work" var: min_work_start category: "People" min: 2 max: 8;
	parameter "Latest hour to start work" var: max_work_start category: "People" min: 8 max: 12;
	parameter "Earliest hour to end work" var: min_work_end category: "People" min: 12 max: 16;
	parameter "Latest hour to end work" var: max_work_end category: "People" min: 16 max: 23;
	parameter "minimal speed" var: min_speed category: "People" min: 0.1 #km / #h;
	parameter "maximal speed" var: max_speed category: "People" max: 10 #km / #h;
	parameter "Value of destruction when a people agent takes a road" var: destroy category: "Road";
	output {
		display city_display type: opengl {
			species building aspect: base;
			species road aspect: base;
			species people aspect: base;
		}

	}

}