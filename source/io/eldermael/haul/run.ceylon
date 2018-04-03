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

suppressWarnings ("expressionTypeNothing")
shared void run() {

    value cliOptions = parseCommandLineArgs(process.arguments);

    if (cliOptions.has("version")) {

        value version = `module io.eldermael.haul`.version;

        print("haul version ``version``");
        process.exit(0);
    }

    value repo = cliOptions.valueOf("repo").string;

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

    "Cannot write to directory ``tempCloneDirName``"
    assert (tempCloneDir.canWrite());


    value gitCloneCommand = "git clone --depth 1 ``repo`` ``tempCloneDirName``";

    value exec = Runtime.runtime.exec(gitCloneCommand);

    exec.waitFor(10, TimeUnit.minutes);

    value propertyFiles = tempCloneDir
        .listFiles()
        .iterable
        .filter((File? file) {
        assert (exists file);

        value isFile = file.file;

        value hasProperExtension = fileExtensions
            .matcher(file.name)
            .matches();

        return isFile
        && hasProperExtension;
    });

    printAll(propertyFiles);

    propertyFiles.each((File? file) {
        assert (exists file);

        if (file.name.endsWith("yaml") ||file.name.endsWith("yml")) {
            value props = Yaml()
                .loadAs(FileReader(file), classForType<Map<String,String>>());

            print(props);
        }

        if (file.name.endsWith("json")) {
            value builder = GsonBuilder().create();

            value props = builder
                .fromJson(FileReader(file), classForType<Map<String,String>>());

            print(props);
        }

        if (file.name.endsWith("properties") || file.name.endsWith("conf")) {
            value props = Properties();
            props.load(FileReader(file));

            print(props);
        }


    });

}

OptionSet parseCommandLineArgs(String[] args) {

    value parser = OptionParser();

    parser.accepts("version");

    parser.accepts("repo")
        .requiredUnless("version")
        .withRequiredArg()
        .ofType(classForType<JavaString>());


    value commandLineOptions = parser.parse(*args);

    return commandLineOptions;
}
