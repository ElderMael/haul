import joptsimple {
    OptionParser,
    OptionSet
}

shared void run() {

    value args = process.arguments;

    value commandLineOptions = parseCommandLineArgs(args);

    if (commandLineOptions.has("version") ){

        value version = `module io.eldermael.haul`.version;

        print("haul version ``version``");
        process.exit(0);
    }

}

OptionSet parseCommandLineArgs(String[] args) {

    value parser = OptionParser();
    parser.accepts("version");

    value commandLineOptions = parser.parse(*args);

    return commandLineOptions;
}
