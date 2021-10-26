<?php
include '../vendor/autoload.php';

use Monolog\Logger;
use Monolog\Handler\StreamHandler;
use Monolog\Formatter\JsonFormatter;

// manage logs properly to stdout, we don't want to write to a file
// On some case, we can push logs to the network, to make log collection easier
$log = new Logger('personio-logs');
$streamHandler = new StreamHandler('php://stdout', ((isset($_ENV['DEBUG']) && $_ENV['DEBUG']) ? Logger::DEBUG : Logger::INFO));
$streamHandler->setFormatter( new JsonFormatter());
$log->pushHandler($streamHandler);

// this demonstrate the application version stored on the container and that can be overriden by env var configuration
$log->debug(sprintf('This is a debug message, with context to help debug procedure'), ['versipn' => $_ENV['APPLICATION_VERSION']]);
$log->info('Information message', ['versipn' => $_ENV['APPLICATION_VERSION']]);

echo "<h2>Personio coding challenge</h2>";
echo "With this <i>wonderful</i> application by Pierre PIRIOU...";
