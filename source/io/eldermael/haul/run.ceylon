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

    value propertiesPerFile = loadKeyAndValuesFromFiles(propertyFiles);

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

{Map<Object,Object>*} loadKeyAndValuesFromFiles({File*} propertyFiles) {

    value propertiesPerFile = propertyFiles.map<Map<Object,Object>?>((File file) {

        "Cannot read file ``file.absolutePath``"
        assert (file.canRead());

        if (file.name.endsWith("yaml") || file.name.endsWith("yml")) {
            value props = Yaml()
                .loadAs(FileReader(file), classForType<Map<Object,Object>>());

            return props;
        }

        if (file.name.endsWith("json")) {
            return ObjectMapper().readValue<Map<Object, Object>>(file, MapType());
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

void dumpToBackends(OptionSet cliOptions, {Map<Object,Object>*} propertiesPerFile) {
    value shouldDumpToConsulCli = cliOptions.has("to-consul-cli");
    if (shouldDumpToConsulCli) {
        dumpProperties(propertiesPerFile, executeDumpCommand("consul kv put '%s' '%s'"));
    }
    value shouldDumpToEtcdCtl = cliOptions.has("to-etcd-cli");
    if (shouldDumpToEtcdCtl) {
        dumpProperties(propertiesPerFile, executeDumpCommand("etcdctl put '%s' '%s'"));
    }
    value shouldDumpToStandardOutput = cliOptions.has("to-stdout");
    if (shouldDumpToStandardOutput) {
        dumpProperties(propertiesPerFile, printToStandardOutput);
    }
}

void dumpProperties({Map<Object,Object>*} propertiesPerFile, Anything(String, String) consumer) {
    propertiesPerFile.each((propertiesInFile) {

        propertiesInFile.entrySet().forEach((entry) {

            value key = entry.key.string;
            value val = entry.\ivalue.string;

            consumer(key, val);

        });

    });
}

Integer executeDumpCommand(String command)(String key, String val) {

    value cliCommand = JavaString.format(command, key, val).split();

    value processBuilder = ProcessBuilder(*cliCommand);

    processBuilder.inheritIO();

    return processBuilder.start().waitFor();

}

void printToStandardOutput(String key, String val) {
    print("``key``=``val``");
}

class MapType() extends TypeReference<Map<String,Object>>() {}
