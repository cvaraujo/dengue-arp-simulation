/**
* Name: DenguePropagation
* Based on the internal empty template. 
* Author: Carlos Araujo
* Tags: 
*/
model DenguePropagation

/* Insert your model definition here */
global {
	int number_S <- 450; // This need to be variable
	int number_I <- 50;
	int number_R <- 0;
	species human {
	}

	species mosquito {
	}

}