CREATE DATABASE IF NOT EXISTS `flights` DEFAULT CHARACTER SET latin1;

USE `flights`;

DROP TABLE IF EXISTS routes;
CREATE TABLE routes
(
    `airportFrom`                varchar(10) NOT NULL,
    `airportTo`                  varchar(20) NOT NULL,
    `connectingAirport`          varchar(10),
    `newRoute`                   bit DEFAULT 0,
    `seasonalRoute`              bit DEFAULT 0,
    `operator`                   varchar(10) NOT NULL,
    `group`                      varchar(10) NOT NULL,
    `tags`                       TEXT,
    `similarArrivalAirportCodes` TEXT,
    `carrierCode`                varchar(10) NOT NULL,
    PRIMARY KEY (airportFrom, airportTo),
    INDEX (airportFrom),
    INDEX (airportTo)
) ENGINE = InnoDB
  DEFAULT CHARSET = latin1;

DROP TRIGGER IF EXISTS NEW_ROUTE;
CREATE TRIGGER NEW_ROUTE
    AFTER INSERT
    ON routes
    FOR EACH ROW
BEGIN
    CALL mysql.lambda_async(
            'RDS-EVENTS-CONSUMER',
            JSON_OBJECT('new', JSON_OBJECT(
                    'airportFrom', NEW.airportFrom,
                    'airportTo', NEW.airportTo,
                    'connectingAirport', NEW.connectingAirport,
                    'newRoute', NEW.newRoute is true,
                    'seasonalRoute', NEW.seasonalRoute is true,
                    'operator', NEW.operator,
                    'group', NEW.group,
                    'tags', NEW.tags,
                    'similarArrivalAirportCodes', NEW.similarArrivalAirportCodes,
                    'carrierCode', NEW.carrierCode)
                )
        );
end;

DROP TRIGGER IF EXISTS UPDATED_ROUTE;
CREATE TRIGGER UPDATED_ROUTE
    AFTER UPDATE
    ON routes
    FOR EACH ROW
BEGIN
    IF (MD5(CONCAT_WS('', NEW.airportFrom, NEW.airportTo, NEW.connectingAirport, NEW.newRoute, NEW.seasonalRoute, NEW.operator, NEW.group, NEW.tags)) <> MD5(CONCAT_WS('', OLD.airportFrom, OLD.airportTo, OLD.connectingAirport, OLD.newRoute, OLD.seasonalRoute, OLD.operator, OLD.group, OLD.tags))) THEN
        CALL mysql.lambda_async(
                'RDS-EVENTS-CONSUMER',
                JSON_OBJECT(
                        'new', JSON_OBJECT(
                        'airportFrom', NEW.airportFrom,
                        'airportTo', NEW.airportTo,
                        'connectingAirport', NEW.connectingAirport,
                        'newRoute', NEW.newRoute is true,
                        'seasonalRoute', NEW.seasonalRoute is true,
                        'operator', NEW.operator,
                        'group', NEW.group,
                        'tags', NEW.tags,
                        'similarArrivalAirportCodes', NEW.similarArrivalAirportCodes,
                        'carrierCode', NEW.carrierCode),
                        'old', JSON_OBJECT(
                        'airportFrom', OLD.airportFrom,
                        'airportTo', OLD.airportTo,
                        'connectingAirport', OLD.connectingAirport,
                        'newRoute', OLD.newRoute is true,
                        'seasonalRoute', OLD.seasonalRoute is true,
                        'operator', OLD.operator,
                        'group', OLD.group,
                        'tags', OLD.tags,
                        'similarArrivalAirportCodes', OLD.similarArrivalAirportCodes,
                        'carrierCode', OLD.carrierCode)
                    )
            );
    end if;
end;

DROP TRIGGER IF EXISTS DELETED_ROUTE;
CREATE TRIGGER DELETED_ROUTE
    AFTER DELETE
    ON routes
    FOR EACH ROW
BEGIN
    CALL mysql.lambda_async(
            'RDS-EVENTS-CONSUMER',
            JSON_OBJECT(
                    'old', JSON_OBJECT(
                            'airportFrom', OLD.airportFrom,
                            'airportTo', OLD.airportTo,
                            'connectingAirport', OLD.connectingAirport,
                            'newRoute', OLD.newRoute is true,
                            'seasonalRoute', OLD.seasonalRoute is true,
                            'operator', OLD.operator,
                            'group', OLD.group,
                            'tags', OLD.tags,
                            'similarArrivalAirportCodes', OLD.similarArrivalAirportCodes,
                            'carrierCode', OLD.carrierCode)
                )
        );
end;