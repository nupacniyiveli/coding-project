import groovy.json.JsonSlurperClassic
import groovy.json.JsonOutput

// Validate input parameters
def validateParameters() {
    if (env.desiredCount.isEmpty()) { error("Missing valid 'desiredCount' environment variable") }
    if (env.containerPort.isEmpty()) { error("Missing valid 'containerPort' environment variable") }
    if (env.awsRegion.isEmpty()) { error("Missing valid 'awsRegion' environment variable") }
    if (env.ecsCluster.isEmpty()) { error("Missing valid 'ecsCluster' environment variable") }
    if (env.dockerRepository.isEmpty()) { error("Missing valid 'dockerRepository' environment variable") }
    if (env.dockerImage.isEmpty()) { error("Missing valid 'dockerImage' environment variable") }
    if (env.ecsAlbTargetGroup.isEmpty()) { error("Missing valid 'ecsAlbTargetGroup' environment variable") }

    if (params.dockerTag.isEmpty()) { error("Missing valid 'dockerTag' parameter") }
}

// configuration
def serviceSwitchOne = "${env.ecsCluster}-${env.dockerImage}__A"
def serviceSwitchTwo = "${env.ecsCluster}-${env.dockerImage}__B"

////
// utils
// Functions can only be called if wrapped on a 'withCredentials' block
// Otherwise, AWS API calls will fails
def getTasksFromService(String service) {
    echo "Listing tasks from service '${service}'"
    def list = sh(returnStdout: true, script: """#!/bin/bash --login
        aws ecs list-tasks --region ${env.awsRegion} --cluster ${env.ecsCluster} --service ${service}
    """).trim()

    return new JsonSlurperClassic().parseText(list)['taskArns']
}

// Wait for the service to be stable
// Otherwise, it'll fail on timeout
def waitForStableService(String service) {
    echo "Waiting [for 2 minutes] for service '${service}' to be stable"

    timeout(time: 2, unit: 'MINUTES') {
        sh """#!/bin/bash --login
            aws ecs wait services-stable \
                --region ${env.awsRegion} \
                --cluster ${env.ecsCluster} \
                --services ${service}
        """
    }
}

// Stop a service (set 'desired count' to 0)
// Deployment is forced, so ECS will drain running tasks
// If asked for, we can manually stop tasks
def stopService(String service) {
    echo "Stop service '${service}'"
    setDesiredCount(service, 0)

    // If asked to do so,
    // we want to manually stop task attached to the service ourself,
    // since ECS can be pretty slow on that part sometine
    if (params.quickStopPreviousVersion) {
        echo "Manually stopping previous running containers"
        def runningTasks = getTasksFromService(service)

        for (def i = 0; i < runningTasks.size(); i++) {
            def currentTask = runningTasks[i]
            echo "Stopping '${currentTask}' task"

            sh """#!/bin/bash --login
                aws ecs stop-task \
                    --region ${env.awsRegion} \
                    --cluster ${env.ecsCluster} \
                    --task ${currentTask} \
                    --reason AskedOnDeployment
            """
        }

        echo "done !"
    }
}

// Update the service, and force the deployment
// Used when we want to start new containers
def deployService(String service) {
    echo "Get task-definition revision id"
    revisionToDeploy = sh(returnStdout: true, script: """#!/bin/bash --login
        aws --region ${env.awsRegion} ecs describe-task-definition --task-definition ${env.ecsCluster}-${env.dockerImage} | jq .taskDefinition.revision
    """).trim().toInteger()

    echo "Update service '${service}' with revision=${revisionToDeploy}"
    sh """#!/bin/bash --login
        aws ecs update-service \
            --region ${env.awsRegion} \
            --cluster ${env.ecsCluster} \
            --service ${service} \
            --deployment-configuration "maximumPercent=100,minimumHealthyPercent=0" \
            --force-new-deployment \
            --desired-count ${env.desiredCount} \
            --task-definition ${env.ecsCluster}-${env.dockerImage}:${revisionToDeploy}
    """
}

// Change the desired count of a service
// Do not change the task definition, only the desired-count property
def setDesiredCount(String service, int desiredCount) {
    echo "Update service '${service}' with DESIRED_COUNT=${desiredCount}"

    sh """#!/bin/bash --login
        aws ecs update-service \
            --region ${env.awsRegion} \
            --cluster ${env.ecsCluster} \
            --service ${service} \
            --deployment-configuration "maximumPercent=100,minimumHealthyPercent=0" \
            --force-new-deployment \
            --desired-count ${desiredCount}
    """
}

// Create a new service
def createService(String service) {
    echo "Get task-definition revision id"
    revisionToDeploy = sh(returnStdout: true, script: """#!/bin/bash --login
        aws --region ${env.awsRegion} ecs describe-task-definition --task-definition ${env.ecsCluster}-${env.dockerImage} | jq .taskDefinition.revision
    """).trim().toInteger()

    echo "Create service '${service}' with revision=${revisionToDeploy}"
    sh """#!/bin/bash --login
        aws ecs create-service \
            --region ${env.awsRegion} \
            --cluster ${env.ecsCluster} \
            --load-balancers "targetGroupArn=${env.ecsAlbTargetGroup},containerName=${env.ecsCluster}-${env.dockerImage},containerPort=${env.containerPort}" \
            --service-name ${service} \
            --deployment-configuration "maximumPercent=100,minimumHealthyPercent=0" \
            --desired-count ${env.desiredCount} \
            --task-definition ${env.ecsCluster}-${env.dockerImage}:${revisionToDeploy}
    """
}

// Rollback the deployment
// This happen if the user ask for it, or if anything fails during the current deployment
// This will:
//   - stop the newly deployed service
//   - start again the previous one
//   - update the job description
//   - set the job status as failed
def rollBackDeployment(String versionToStop, String versionToRestart) {
    echo "Rolling back deployment"
    echo "${versionToStop} will be stopped, and ${versionToRestart} will restart"

    // force the tasks to stop as fast as possible
    params.quickStopPreviousVersion = true
    stopService(versionToStop)

    // make the service online again by setting it desired-count to something > 0
    setDesiredCount(versionToRestart, env.desiredCount)

    // Update build description to make it clear it has been rollbacked
    def desc = currentBuild.description
    currentBuild.description = "/!\\ ROLLBACK DONE /!\\ " + desc

    // Also set the job status as aborted
    currentBuild.result = 'ABORTED'
}

// get task-definition
def downloadTaskDefinition() {
    echo "Check 'docker/${env.dockerImage}/${env.ecsCluster}/services/${env.dockerImage}.json' on S3"
    sh """#!/bin/bash --login
        aws s3 ls s3://SECRET-BUCKET/docker/${env.dockerImage}/${env.ecsCluster}/services/${env.dockerImage}.json

        if [[ \$? -ne 0 ]]; then
            echo 's3://SECRET-BUCKET/docker/${env.dockerImage}/${env.ecsCluster}/services/${env.dockerImage}.json does not exists !'
            exit 1
        fi
    """

    echo "Download 'docker/${env.dockerImage}/${env.ecsCluster}/services/${env.dockerImage}.json' from S3 to local file: '${env.dockerImage}-${BUILD_NUMBER}.json'"
    sh """#!/bin/bash --login
        aws s3 cp s3://SECRET-BUCKET/docker/${env.dockerImage}/${env.ecsCluster}/services/${env.dockerImage}.json ${env.dockerImage}-${BUILD_NUMBER}.json
    """
}

// get configuration
def downloadConfiguration() {
    echo "Check 'docker/${env.dockerImage}/${env.ecsCluster}/services/${env.dockerImage}.env.json' on S3"
    sh """#!/bin/bash --login
        aws s3 ls s3://SECRET-BUCKET/docker/${env.dockerImage}/${env.ecsCluster}/services/${env.dockerImage}.env.json

        if [[ \$? -ne 0 ]]; then
            echo 's3://SECRET-BUCKET/docker/${env.dockerImage}/${env.ecsCluster}/services/${env.dockerImage}.env.json does not exists !'
            exit 1
        fi
    """

    echo "Download 'docker/${env.dockerImage}/${env.ecsCluster}/services/${env.dockerImage}.env.json' from S3 to local file: '${env.dockerImage}-${BUILD_NUMBER}.env.json'"
    sh """#!/bin/bash --login
        aws s3 cp s3://SECRET-BUCKET/docker/${env.dockerImage}/${env.ecsCluster}/services/${env.dockerImage}.env.json ${env.dockerImage}-${BUILD_NUMBER}.env.json
    """
}

// Merge configuration file into task-definition file
def mergeConfigurationToTaskDefinition(configurationFilePath, taskDefinitionFilePath) {
    def taskDefinitionContent = readFile(taskDefinitionFilePath)
    def configurationContent = readFile(configurationFilePath)

    def task = new JsonSlurperClassic().parseText(taskDefinitionContent)
    def configuration = new JsonSlurperClassic().parseText(configurationContent)

    def environmentList = []
    for (def i = 0; i < configuration.size(); i++) {
        echo "Parsing ${configuration[i].name}"
        def parameter = [:]

        parameter['name'] = configuration[i].name
        parameter['value'] = configuration[i].value
        environmentList.push(parameter)
    }

    // merge content
    task.containerDefinitions[0].environment = task.containerDefinitions[0].environment.plus(configuration)

    // set the correct docker image
    task.containerDefinitions[0].image = env.dockerRepository + "/" + env.dockerImage + ":" + params.dockerTag.replaceAll("[^-a-zA-Z0-9:._ ]", "").replaceAll("\\s", "").trim()

    // write file
    def result = JsonOutput.toJson(task)
    writeFile file: taskDefinitionFilePath, text: result
}

timestamps {
    node() {
        script {
            // sanitize
            def dockerTag = params.dockerTag.replaceAll("[^-a-zA-Z0-9:._ ]", "").replaceAll("\\s", "").trim()

            currentBuild.description = "Deploying ${env.dockerRepository}/${env.dockerImage}:${dockerTag}. \nCluster:${env.ecsCluster}, region:${env.awsRegion}"
        }

        stage('Init') {
            sh """#!/bin/bash --login
                rm -f *.json
            """

            validateParameters()
        }

        stage('Check docker tag') {
            // sanitize
            def dockerTag = params.dockerTag.replaceAll("[^-a-zA-Z0-9:._ ]", "").replaceAll("\\s", "").trim()

            withCredentials([usernamePassword(credentialsId: 'dockerHubCredentials', usernameVariable: 'DOCKER_REGISTRY_USER', passwordVariable: 'DOCKER_REGISTRY_PASSWORD')]) {
                def imageId = sh(
                    returnStdout: true,
                    script: """#!/bin/bash --login
                        DOCKER_HUB_TOKEN=\$(curl -sSLd "username=\${DOCKER_REGISTRY_USER}&password=\${DOCKER_REGISTRY_PASSWORD}" https://hub.docker.com/v2/users/login | jq -r ".token" )
                        curl -sH "Authorization: JWT \${DOCKER_HUB_TOKEN}" "https://hub.docker.com/v2/repositories/${env.dockerRepository}/${env.dockerImage}/tags/${dockerTag}/" | jq .id
                    """
                ).trim()

                if (imageId == 'null') {
                    error("Docker image '${env.dockerRepository}/${env.dockerImage}:${dockerTag}' does not exists in DockerHub")
                }
            }
        }

        stage('Retrieve & populate task definition') {
            echo "Download task-definition"
            withCredentials([usernamePassword(credentialsId: 'application-secrets-bucket-user', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                downloadTaskDefinition()
            }

            echo "Retrieving configuration"
            withCredentials([usernamePassword(credentialsId: 'application-secrets-bucket-user', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                downloadConfiguration()
            }

            echo "Merging configuration into task definition"
            mergeConfigurationToTaskDefinition("${env.dockerImage}-${BUILD_NUMBER}.env.json", "${env.dockerImage}-${BUILD_NUMBER}.json")
        }

        stage('Register task definition') {
            echo "Register the task-definition. It'll create a new one or create a new revision, based on the family name"
            echo "family: ${env.ecsCluster}-${env.dockerImage}"

            withCredentials([usernamePassword(credentialsId: 'ecs-ec2-user', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                wrap([$class: 'AnsiColorBuildWrapper', 'colorMapName': 'xterm']) {
                    sh """#!/bin/bash --login
                        aws --region ${env.awsRegion} ecs register-task-definition \
                            --family ${env.ecsCluster}-${env.dockerImage} \
                            --cli-input-json file://${env.dockerImage}-${BUILD_NUMBER}.json
                    """
                }
            }
        }

        stage('Canary deployment') {
            /*
                Test if service__A exists and what is desiredCount on it
                Test if service__B exists and what is desiredCount on it

                if service__A don't exists, create it: it's first deployment.
                Don't create service__B

                if service__B don't exists, create it: it's second deployment.
                Once done, set service__A desired count to 0

                else, service__B exists, with desired count > 0
                update service__A
                Once done, set service__B desired count to 0
            */
            withCredentials([usernamePassword(credentialsId: 'ecs-ec2-user', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                echo "Check '${serviceSwitchOne}' status"
                serviceOneFailures = sh(returnStdout: true, script: """#!/bin/bash --login
                    aws --region ${env.awsRegion} ecs describe-services --cluster ${env.ecsCluster} --services ${serviceSwitchOne} | jq .failures[]
                """).trim()

                if (serviceOneFailures != "") {
                    ////
                    // First deployment
                    echo "Service '${serviceSwitchOne}' doesn't exist"

                    try {
                        createService(serviceSwitchOne)
                        echo "First deployment done, congratulation !"
                    } catch ($e) {
                        echo "An error occured: ${e}"
                        echo "Since it's the first deployment ever, nothing will be done"
                    }
                } else {
                    echo "Service '${serviceSwitchOne}' exists"
                    echo "This is not the first deployment"

                    echo "Check '${serviceSwitchTwo}' status"
                    serviceTwoFailures = sh(returnStdout: true, script: """#!/bin/bash --login
                        aws --region ${env.awsRegion} ecs describe-services --cluster ${env.ecsCluster} --services ${serviceSwitchTwo} | jq .failures[]
                    """).trim()

                    if (serviceTwoFailures != "") {
                        ////
                        // Second deployment
                        echo "Service '${serviceSwitchTwo}' doesn't exist"

                        createService(serviceSwitchTwo)
                        echo "The deployment is now 50/50 old/new version"

                        try {
                            waitForStableService(serviceSwitchTwo)

                            // waiting for user input if asked for
                            if (params.pauseDeployment) {
                                echo "You now have 4 hours to answer this question, otherwise the deployment will rollback"
                                timeout(time: 4, unit: 'HOURS') {
                                    userInput = input(message: 'Can the new version replace 100% of the previous one deployed ?')
                                }
                            }

                            stopService(serviceSwitchOne)
                        } catch (e) {
                            echo "An error occured: ${e}"
                            rollBackDeployment(serviceSwitchTwo, serviceSwitchOne)
                        }
                    } else {
                        ////
                        // >N+2 deployment case
                        echo "This is, at least, the third deployment"

                        def nonActiveService = serviceSwitchOne
                        def activeService = serviceSwitchTwo

                        // Here we need to check which service have a 'desiredCount' of 0, which is the inactive service.
                        // We'll use this service to launch the new task-definition revision
                        serviceTwoDesiredCount = sh(returnStdout: true, script: """#!/bin/bash -l
                            aws ecs describe-services \
                                --region ${env.awsRegion} \
                                --cluster ${env.ecsCluster} \
                                --services ${serviceSwitchTwo} \
                                --query 'services[0].desiredCount' \
                                --output text
                            """).trim().toInteger()

                        if (serviceTwoDesiredCount == 0) {
                            echo "Service '${serviceSwitchTwo}' is the non-active service"

                            nonActiveService = serviceSwitchTwo
                            activeService = serviceSwitchOne
                        } else {
                            echo "Service '${serviceSwitchOne}' is the non-active service"
                        }

                        try {
                            echo "Launching new service (currently inactive service '${nonActiveService}')"
                            deployService(nonActiveService)

                            echo "The deployment is now 50/50 old/new version"

                            waitForStableService(nonActiveService)

                            // waiting for user input if asked for
                            if (params.pauseDeployment) {
                                echo "You now have 4 hours to answer this question, otherwise the deployment will rollback"
                                timeout(time: 4, unit: 'HOURS') {
                                    userInput = input(message: 'Can the new version replace 100% of the previous one deployed ?')
                                }
                            }

                            stopService(activeService)
                        } catch (e) {
                            echo "An error occured: ${e}"
                            rollBackDeployment(nonActiveService, activeService)
                        }
                    }
                }
            }

            echo "Process is now over !"
        }

        stage('Cleanup') {
            sh """#!/bin/bash --login
                rm -f ${env.dockerImage}-${BUILD_NUMBER}.json
                rm -f ${env.dockerImage}-${BUILD_NUMBER}.env.json
            """
        }
    }
}
