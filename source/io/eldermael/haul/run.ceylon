import joptsimple {
    OptionParser,
    OptionSet
}
import java.lang {
    JavaString=String,
    ProcessBuilder,
    Types {
        classForType
    },
    Runtime,
    System
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
import com.fasterxml.jackson.core.type {
    TypeReference
}
import com.fasterxml.jackson.databind {
    ObjectMapper
}

Pattern fileExtensions = Pattern
    .compile("([^\\s]+(\\.(?i)(ya?ml|properties|json|conf))$)");

variable Boolean verbose = false;

shared void run() {

    value cliOptions = parseCommandLineArgs(process.arguments);

    value shouldPrintVersionAndExit = cliOptions.has("version");

    if (shouldPrintVersionAndExit) {
        printVersionAndExit();
    }

    value tempDir = cliOptions.valueOf("temp-dir").string;
    value repositoryUrl = cliOptions.valueOf("repo").string;

    value gitRepoDirectory = cloneGitRepo(repositoryUrl, tempDir);

    value propertyFiles = searchConfigFilesInDirectory(gitRepoDirectory);

    {[File, Map<Object,Object>]*} propertiesPerFile =
            loadKeyAndValuesFromFiles(propertyFiles)
            .coalesced;

    dumpToBackends(cliOptions, propertiesPerFile);

}

OptionSet parseCommandLineArgs(String[] args) {

    value parser = OptionParser();

    parser.accepts("version");

    parser.accepts("repo")
        .requiredUnless("version")
        .withRequiredArg()
        .ofType(classForType<JavaString>());

    parser.accepts("to-consul-cli");
    parser.accepts("to-etcd-cli");

    parser.accepts("to-stdout");

    parser.accepts("temp-dir")
        .withRequiredArg()
        .ofType(classForType<JavaString>())
        .defaultsTo(JavaString(System.getProperty("java.io.tmpdir")));

    parser.accepts("verbose");

    value commandLineOptions = parser.parse(*args);

    return commandLineOptions;
}

suppressWarnings ("expressionTypeNothing")
void printVersionAndExit() {
    value version = `module io.eldermael.haul`.version;
    print("haul version ``version``");
    process.exit(0);
}

File cloneGitRepo(String repositoryUrl, String tempDir) {
    value repoPath = URL(repositoryUrl).path;
    value indexAfterLastSlash = repoPath.lastIndexOf("/") + 1;

    value repoName = repoPath
        .substring(indexAfterLastSlash, repoPath.size)
        .replace(".git", "");

    value tempCloneDirName = "``tempDir``/``repoName``";

    value tempCloneDir = File(tempCloneDirName);

    if (tempCloneDir.\iexists()) {
        tempCloneDir.delete();
    }

    tempCloneDir.mkdirs();

    "Cannot create directory '``tempCloneDirName``'"
    assert (tempCloneDir.\iexists());

    value gitCloneCommand = "git clone --depth 1 ``repositoryUrl`` ``tempCloneDirName``";

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

{ [ File, Map<Object,Object> ]?* } loadKeyAndValuesFromFiles({File*} propertyFiles) {

    value propertiesPerFile = propertyFiles.map<[ File, Map<Object,Object> ]?>((File file) {

        "Cannot read file ``file.absolutePath``"
        assert (file.canRead());

        if (file.name.endsWith("yaml") || file.name.endsWith("yml")) {
            value props = Yaml()
                .loadAs(FileReader(file), classForType<Map<Object,Object>>());

            return [ file, props ];
        }

        if (file.name.endsWith("json")) {
            value props = ObjectMapper()
                .readValue<Map<Object, Object>>(file, MapType());
            return [ file, props ];
        }

        if (file.name.endsWith("properties") || file.name.endsWith("conf")) {
            value props = Properties();
            props.load(FileReader(file));

            return [ file, props ];
        }

        return null;

    }).coalesced;

    return propertiesPerFile;
}

void dumpToBackends(OptionSet cliOptions, {[File, Map<Object,Object>]*} propertiesPerFile) {

    verbose = cliOptions.has("verbose");

    value shouldDumpToConsulCli = cliOptions.has("to-consul-cli");
    if (shouldDumpToConsulCli) {
        dumpProperties(propertiesPerFile,
            executeDumpCommand("consul", "kv", "put", "%k", "%v"));
    }

    value shouldDumpToEtcdCtl = cliOptions.has("to-etcd-cli");
    if (shouldDumpToEtcdCtl) {
        dumpProperties(propertiesPerFile,
            executeDumpCommand("etcdctl", "put", "%k", "%v"));
    }

    value shouldDumpToStandardOutput = cliOptions.has("to-stdout");
    if (shouldDumpToStandardOutput) {
        dumpProperties(propertiesPerFile, printToStandardOutput);
    }
}

void dumpProperties({[File, Map<Object,Object>]*} propertiesPerFile,
        Anything(String, String) consumer) {

    propertiesPerFile.each((propertiesInFile) {

        value [file, properties] = propertiesInFile;

        if(verbose) {
            print("Dumping file: '``file.absolutePath``'");
        }


        properties.entrySet().forEach((entry) {

            value key = entry.key.string;
            value val = entry.\ivalue.string;

            consumer(key, val);

        });

    });
}

Integer executeDumpCommand(String* command)(String key, String val) {

    value commandWithArgs = command.map((part){

        if(part == "%k") {
            return key;
        }

        if(part == "%v") {
            return val;
        }

        return part;
    });

    value processBuilder = ProcessBuilder(*commandWithArgs);

    if(verbose) {
        processBuilder.inheritIO();
    }

    return processBuilder
        .start()
        .waitFor();

}

void printToStandardOutput(String key, String val) {
    print("``key``=``val``");
}

class MapType() extends TypeReference<Map<String,Object>>() {}
