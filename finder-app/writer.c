#include<stdio.h>
#include<stdlib.h>
#include<syslog.h>
#include<string.h>

int main(int argc, char *argv[]){
	openlog("writer",LOG_PID,LOG_USER);

	if(argc != 3){
		syslog(LOG_ERR, "Error: Incorrect number of arguments. Usage: %s <file_path><text_string>", argv[0]);
		fprintf(stderr, "Usage: %s <file_path> <text_string>\n", argv[0]);
       		exit(1);
   	}
	const char *file_path = argv[1];
   	const char *text_string = argv[2];

   	// Open the file for writing (overwrite mode)
   	FILE *file = fopen(file_path, "w");
   	if (file == NULL) {
   		syslog(LOG_ERR, "Error: Could not open file %s for writing", file_path);
       		perror("Error opening file");
       		exit(1);
   	}

   	// Write the string to the file
   	if (fprintf(file, "%s\n", text_string) < 0) {
       		syslog(LOG_ERR, "Error: Failed to write to file %s", file_path);
       		perror("Error writing to file");
       		fclose(file);
       		exit(1);
   	}

    	// Log the success message
    	syslog(LOG_DEBUG, "Writing \"%s\" to %s", text_string, file_path);

    	// Close the file and syslog
    	fclose(file);
    	closelog();
	
    	return 0;
}
