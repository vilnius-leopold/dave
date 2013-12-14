CREATE TABLE `scheme_change_log` (
	`id` INT NOT NULL AUTO_INCREMENT,
	`major_release_number` INT NOT NULL,
	`minor_release_number` INT NOT NULL,
	`point_release_number` INT NOT NULL,
	`comment` VARCHAR(255) NULL,
	`title` VARCHAR(45) NULL,
	`file_name` VARCHAR(45) NOT NULL,
	PRIMARY KEY (`id`));