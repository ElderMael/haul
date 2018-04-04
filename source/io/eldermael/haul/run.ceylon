import joptsimple {
    OptionParser,
    OptionSet
}
import java.lang {
    JavaString=String,

    Types {
        classForType
    },
    Runtime
}
import java.net {
    URL
}
import java.io {
    File,
    FileReader
}
import java.util.concurrent {
    TimeUnit
}
import java.util.regex {
    Pattern
}
import org.yaml.snakeyaml {
    Yaml
}
import java.util {
    Map,
    Properties
}
import com.google.gson {
    GsonBuilder
}

Pattern fileExtensions = Pattern
    .compile("([^\\s]+(\\.(?i)(ya?ml|properties|json|conf))$)");


shared void run() {

    value cliOptions = parseCommandLineArgs(process.arguments);

    value shouldPrintVersionAndExit = cliOptions.has("version");

    if (shouldPrintVersionAndExit) {
        printVersionAndExit();
    }

    value repositoryUrl = cliOptions.valueOf("repo").string;

    value gitRepoDirectory = cloneGitRepo(repositoryUrl);

    value propertyFiles = searchConfigFilesInDirectory(gitRepoDirectory);

    value propertiesPerFile = loadKeyAndValuesFromFiles(propertyFiles);

    value shouldDumpToConsulCli = cliOptions.has("to-consul-cli");

    if (shouldDumpToConsulCli) {
        dumpPropertiesToConsulCli(propertiesPerFile);
    }

}

OptionSet parseCommandLineArgs(String[] args) {

    value parser = OptionParser();

    parser.accepts("version");

    parser.accepts("repo")
        .requiredUnless("version")
        .withRequiredArg()
        .ofType(classForType<JavaString>());

    parser.accepts("to-consul-cli");


    value commandLineOptions = parser.parse(*args);

    return commandLineOptions;
}

suppressWarnings ("expressionTypeNothing")
void printVersionAndExit() {
    value version = `module io.eldermael.haul`.version;
    print("haul version ``version``");
    process.exit(0);
}

File cloneGitRepo(String repo) {
    value repoPath = URL(repo).path;
    value indexAfterLastSlash = repoPath.lastIndexOf("/") + 1;

    value repoName = repoPath
        .substring(indexAfterLastSlash, repoPath.size)
        .replace(".git", "");

    value tempCloneDirName = "/tmp/``repoName``";

    value tempCloneDir = File(tempCloneDirName);

    if (tempCloneDir.\iexists()) {
        tempCloneDir.delete();
    }

    tempCloneDir.mkdirs();

    value gitCloneCommand = "git clone --depth 1 ``repo`` ``tempCloneDirName``";

    value cloningProcess = Runtime.runtime.exec(gitCloneCommand);

    cloningProcess.waitFor(10, TimeUnit.minutes);

    return tempCloneDir;
}

{File*} searchConfigFilesInDirectory(File gitRepoDirectory) {
    value propertyFiles = gitRepoDirectory
        .listFiles()
        .iterable
        .filter((File? file) {
            assert (exists file);

            value isFile = file.file;

            value hasProperExtension = fileExtensions
                .matcher(file.name)
                .matches();

            return isFile && hasProperExtension;
        }).coalesced;

    return propertyFiles;
}

{Map<Object,Object>*} loadKeyAndValuesFromFiles({File*} propertyFiles) {

    value propertiesPerFile = propertyFiles.map<Map<Object,Object>?>((File file) {

        "Cannot read file ``file.absolutePath``"
        assert (file.canRead());

        if (file.name.endsWith("yaml") ||file.name.endsWith("yml")) {
            value props = Yaml()
                .loadAs(FileReader(file), classForType<Map<Object,Object>>());

            return props;
        }

        if (file.name.endsWith("json")) {
            value builder = GsonBuilder().create();

            value props = builder
                .fromJson(FileReader(file), classForType<Map<Object,Object>>());

            return props;
        }

        if (file.name.endsWith("properties") ||file.name.endsWith("conf")) {
            value props = Properties();
            props.load(FileReader(file));

            return props;
        }

        return null;

    }).coalesced;

    return propertiesPerFile;
}

void dumpPropertiesToConsulCli({Map<Object,Object>*} propertiesPerFile) {
    propertiesPerFile.each((map) {

        map.entrySet().forEach((entry) {

            value command = "consul kv put '``entry.key.string``' '``entry.\ivalue.string``'";

            print("Running: ``command``");

            Runtime
                .runtime
                .exec(command);
        });

    });
}
