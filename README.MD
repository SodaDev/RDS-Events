RDS Streams

You've probably have heard about DynamoDB Streams, in this article I will check how we can achieve similar behaviour using cloud optimized database Amazon Aurora.

If this is a first time you've heard about DynamoDB Streams here is quick recap. DynamoDB Streams is mechanism from Amazon DynamoDB which captures all document level changes and triggers events with those changes.

Motivation

I've heard a lot of times that teams are missing event sourcing feature in SQL databases. Especially after switching from DynamoDB. It would be cool to make that easier for them. Right? Let's see what we can do about it.



Plan

It would be great to stream all records changes to the stream exactly like it's done on DynamoDB. How to do it? It would be awesome to put those events into some streaming solution like Kinesis or messaging like SQS or even SNS. Yet, it's not possible directly.

Amazon Aurora has integration with other AWS services (like S3, Lambda, ML with SageMaker and Comprehend). In this article I will focus on the intgration with AWS Lambda as it looks like best solution for this particular case. One of the features that is available in Aurora exclusively is SQL function responsible for Lambda invocation. This function is called lambda_async which has signatute

    lambda_async(<Your lambda function arn>, <Your JSON payload>)

Sounds promising. Let's see what we can achieve with it.



Environment setup

If you don't want to setup your environment and play with it on your own just skip this section

First things first. To start playing with it we have to setup our database. I won't use AWS Console for achieving that goal to give you opportunity to play with exactly same setup as I have. This is why I have prepared IaaC using Cloudformation.



What we are going to setup?

- Lambda function
  RDS Events consumer that will log incoming events from Aurora <PUT HERE LINK TO GITHUB>. It's basic function that only logs input in NodeJS. Nothing fancy here.
- Network setup
  I didn't want to put any mess in your AWS account. This is why I will setup my own VPC for this scenario. Network setup which can be found here <PUT HERE LINK TO GITHUB> and consists of:
    - VPC
    - Public subnet for bastion host
        - Internet gateway to enable your public subnet to communicate with the internet
    - Private subnets for Aurora
        - Single NAT gateway with Elastic IP attached
    - Routing for private and public subnets
      If you already have some VPC which has colliding CIDR blocks you will have to adjust them.
- Aurora with security setup and bastion host to access it
  Please keep in mind that lambda invocation from SQL does not work with Aurora Serverless


If you don't want to run this Cloudformation against your AWS account and want to setup Aurora on your own using AWS console. Please do keep in mind couple of things.

Networking

Aurora calls your lambda and to make it possible it has to communicate with AWS Lambda through internet. For that particular reason it is important where exactly you are going to deploy your Aurora cluster. Below there is small set of rules.

- Public subnet
    - You are going to use public database?  You are good to go.
    - You are going to use private database? Despite that DB is in public subnet it still is private. Yet it has to communicate with the internet. You have to route your traffic through NAT or VPC endpoints for integration with other AWS Services. More info can be found in AWS documentation.
- Private subnet
    - You have to setup NAT in your public subnet and route your private subnet traffic through NAT to enable communication between Aurora instances and the Internet. (This is done in the example Cloudformation)

RDS IAM setup

Whenever Aurora invokes lambda function it must have privileges to do it. It's done through IAM roles. You've got to create a role with policy and assign it to the RDS as well as to put it in custom parameter group. You can find instructions here and here.



How to deploy it?

1. Log in the CLI to your AWS account
2. Get repo <PUT GITHUB LINK HERE>
3. Update parameters in deploy.sh
    1. Setup password
    2. Set you bastion key name
       If you don't have ssh key create it using this guide
4. Run ./bin/deploy.sh

How to access it?

You've got to connect to your RDS cluster through bastion tunnel

I like to use terminal

I have occupied local 3306 port so have replaced it with 33306.

In bin/openTunnel.sh replace ~/.ssh/bastion-key.pem with path to you ssh key and run it.

Now you can connect to mysql through localhost:33306 with the root user and password that you have set up.

I don't like to user terminal

This setup will be based on usage of IntelliJ.

1. In IntelliJ add your data source. You can get rds endpoint by running

   aws rds describe-db-clusters --db-cluster-identifier rds-events-cluster | jq -r '.DBClusters[].Endpoint'



2. Setup SSH tunnel

Switch to SSH/SSL tab.



Put there bastion IP as well as path to your ssh key. You can get bastion IP by running

    aws ec2 describe-instances --filters Name=tag:Name,Values='RDS Events Bastion' | jq -r '.Reservations[].Instances[].PublicIpAddress'





Setting up DB schema

For simplicity of the example I have created simple database names flights which has table with flight routes (with usage of Ryanair's publicly available data). It's very easy model which is obvious for everyone. We would like to setup scenario in which there will be notification sent whenever new route will be registered in the SQL database.

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

I didn't want to create custom resource to make Cloudformation scripts easy to read. If you are interested in creating such customer resources write a comment. I can extend Cloudformation with such custom resource if you are curious how to create one.

If you want to load data into database you can use data defined in csv file data/routes.sql.

Worth to note that if you have specific user on Aurora which is used for connection. You've got to grant him permissions to invoke lambda functions with:

    GRANT INVOKE LAMBDA ON *.* TO user@domain-or-ip-address



Setting up trigger

The whole purpose of this article was to create SQL mechanism to track all changes in the data. We can use native SQL mechanism for that and setup triggers. DynamoDB emits events for every data change with old and new values. How can we achieve such mechanism?

Unfortunately there is no out-of-the-box solution like in DynamoDB. We've got to set it up on our own. We are going to define three separate triggers for this action. It could be cumbersome for really big entities. Yet, not sure if there is any possible solution to make it work on the whole object. Fortunately we are working with structured data.

We can setup 3 types of triggers here:

- Insert trigger - to capture new items
- Delete trigger - to capture deleted items
- Update items - to capture item before and after modification. We have to add there additional condition to not trigger events in case of UPDATE action which is not modifying the data itself.



Invoking lambda

Before setting up our triggers, let's first check if we are able to invoke our lambda function. Let's run in SQL

    CALL mysql.lambda_async('RDS-EVENTS-CONSUMER', '{}')

And you should be able to see log in your Cloudwatch logs here



INSERT

First we have to create our trigger in the DB.

    DROP TRIGGER IF EXISTS NEW_ROUTE;
    CREATE TRIGGER NEW_ROUTE
        AFTER INSERT
        ON routes
        FOR EACH ROW
    BEGIN
        CALL mysql.lambda_async(
                'arn:aws:lambda:eu-west-1:294104603975:function:RDS-EVENTS-Auditor-Q4UQVYNOJ-RDSEventsLoggerLambda-H2Q2LV1BM4KU',
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

Now we can check how it works by executing

    INSERT INTO flights.routes (airportFrom, airportTo, connectingAirport, newRoute, seasonalRoute, operator, `group`, tags, similarArrivalAirportCodes, carrierCode) VALUES ('FOO', 'BAR', null, false, false, 'RYANAIR', 'CITY', '', '', 'FR');

We can find in Cloudwatch Logs event with our change



DELETE

First we have to create our trigger in the DB.

    DROP TRIGGER IF EXISTS DELETED_ROUTE;
    CREATE TRIGGER DELETED_ROUTE
        AFTER DELETE
        ON routes
        FOR EACH ROW
    BEGIN
        CALL mysql.lambda_async(
                'arn:aws:lambda:eu-west-1:294104603975:function:RDS-EVENTS-Auditor-Q4UQVYNOJ-RDSEventsLoggerLambda-H2Q2LV1BM4KU',
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

Now we can check how it works by executing

    DELETE FROM flights.routes WHERE airportFrom = 'FOO' AND airportTo = 'BAR';

We can find in Cloudwatch Logs event with our change



UPDATE

First we have to create our trigger in the DB. I have used md5 for checking if content of any field have changed to limit number of events triggered in case of updates resulting in no mutations.

    DROP TRIGGER IF EXISTS UPDATED_ROUTE;
    CREATE TRIGGER UPDATED_ROUTE
        AFTER UPDATE
        ON routes
        FOR EACH ROW
    BEGIN
        IF (MD5(CONCAT(NEW.airportFrom, NEW.airportTo, NEW.connectingAirport, NEW.newRoute, NEW.seasonalRoute, NEW.operator, NEW.group, NEW.tags)) <> MD5(CONCAT(OLD.airportFrom, OLD.airportTo, OLD.connectingAirport, OLD.newRoute, OLD.seasonalRoute, OLD.operator, OLD.group, OLD.tags))) THEN
            CALL mysql.lambda_async(
                    'arn:aws:lambda:eu-west-1:294104603975:function:RDS-EVENTS-Auditor-Q4UQVYNOJ-RDSEventsLoggerLambda-H2Q2LV1BM4KU',
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

Now we can check how it works by first adding item from insert example and then modify it by executing.

    INSERT INTO flights.routes (airportFrom, airportTo, connectingAirport, newRoute, seasonalRoute, operator, `group`, tags, similarArrivalAirportCodes, carrierCode) VALUES ('FOO', 'BAR', null, false, false, 'RYANAIR', 'CITY', '', '', 'FR');
    UPDATE flights.routes SET newRoute = true WHERE airportFrom = 'FOO' AND airportTo = 'BAR';

We can find in Cloudwatch Logs event with our change





So as you can see it works with streaming data change events to the AWS Lambda which gives us unlimited opportunities.



Considerations

Lambda throttling

I have tested lambda throttling behaviour by setting up ReservedConcurrentExecutions to 0 and inserting multiple elements. After that I have set up ReservedConcurrentExecutions to 10. Your transaction will be safe in case of lambda being throttled and you will receive notification with a delay. Yet it will be delivered. Lambda retry policy apply here. I would advise to set up dead letter queue.



Lambda invocation failure in transaction

With usage of asychronous invocation we are limiting number of issues that could happen inside our transaction (and this is where TRIGGER logic is invoked). Major issues that can happen regarding lambda invocation failure in Aurora are:

- Malformed ARN: In case of lambda failure due to wrong arn you won't be able to commit transaction and it can impact the system.
- Insufficient permissions: In case of insufficient permissions you won't be able to commit transaction.

During tests I have found out that function name works as well as function arn

Lambda failure

In case of lambda failure your transaction is safe. Triggering lambda won't affect it. AWS will try to invoke your lambda multiple times. I would advise to set up dead letter queue.



Performance

Performance impact is massive. I haven't run any exhaustive testing after seeing the first results. I have runned simple insert with multiple values that you can find in data/routes.sql file.

Here are mine results:

- No triggers
  [2021-02-01 19:02:47] 1,999 rows affected in 836 ms
  [2021-02-01 19:17:02] 1,999 rows affected in 885 ms
- Triggers
  [2021-02-01 19:07:36] 1,999 rows affected in 1 m 10 s 462 ms
  [2021-02-01 19:14:18] 1,999 rows affected in 1 m 11 s 377 ms

Network failure

Let's simulate network failure. I did it by detaching NAT Gateway from routing table. Now our Aurora can't connect to the internet. After that we could try to insert new item.

    INSERT INTO flights.routes (airportFrom, airportTo, connectingAirport, newRoute, seasonalRoute, operator, `group`, tags, similarArrivalAirportCodes, carrierCode) VALUES ('FOO', 'NETWORK_FAILURE', null, false, false, 'RYANAIR', 'CITY', '', '', 'FR');

As an effect write will hang for a looooong time and eventually will fail.

Ghost notifications

This is the major issue I have found with that approach. Trigger logic is invoked inside transaction. What will happen if it will fail? Whole transaction will fail. What is worth consideration is asking yourself a question What will happen if transaction will fail due to data modification operations inside transaction?. This one is pretty scary if you will use this feature to some critical operations. Imagine such scenario:

    START TRANSACTION;
    
    INSERT INTO flights.routes (airportFrom, airportTo, connectingAirport, newRoute, seasonalRoute, operator, `group`, tags, similarArrivalAirportCodes, carrierCode) VALUES ('FOO', 'ROLLBACK_1', null, false, false, 'RYANAIR', 'CITY', '', '', 'FR');
    INSERT INTO flights.routes (airportFrom, airportTo, connectingAirport, newRoute, seasonalRoute, operator, `group`, tags, similarArrivalAirportCodes, carrierCode) VALUES ('FOO', 'ROLLBACK_2', null, false, false, 'RYANAIR', 'CITY', '', '', 'FR');
    INSERT INTO flights.routes (airportFrom, airportTo, connectingAirport, newRoute, seasonalRoute, operator, `group`, tags, similarArrivalAirportCodes, carrierCode) VALUES ('FOO', 'ROLLBACK_3', null, false, false, 'RYANAIR', 'CITY', '', '', 'FR');
    
    ROLLBACK;

You hope that lambda won't be invoked? Yeah, I would like that too, but it's not the real behaviour. In such situation we will get lambda invocations for all three INSERTS.





Use cases

- change notifications
- Old solution that was lift and shifted to the cloud with legacy code
- 3rd party solution compatible with MySQL, yet not modifiable by your team
- Adding TTL like behaviour to the MySQL
- Preparing static content with usage of SQL structure goodies



Drawbacks

Note - here we won't have guaranteed order
