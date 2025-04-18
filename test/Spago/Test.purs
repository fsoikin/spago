module Test.Spago.Test where

import Test.Prelude

import Data.Array as Array
import Data.String as String
import Node.Platform as Platform
import Node.Process as Process
import Registry.Version as Version
import Spago.Command.Init (DefaultConfigOptions(..))
import Spago.Command.Init as Init
import Spago.Core.Config as Config
import Spago.FS as FS
import Spago.Path as Path
import Spago.Paths as Paths
import Test.Spec (Spec)
import Test.Spec as Spec
import Test.Spec.Assertions as Assert

spec :: Spec Unit
spec = Spec.around withTempDir do
  Spec.describe "test" do

    Spec.it "tests successfully" \{ spago, fixture } -> do
      spago [ "init", "--name", "7368613235362d6a336156536c675a7033334e7659556c6d38" ] >>= shouldBeSuccess
      spago [ "build" ] >>= shouldBeSuccess
      spago [ "test" ] >>= shouldBeSuccessOutputWithErr (fixture "test-output-stdout.txt") (fixture "test-output-stderr.txt")

    Spec.it "tests successfully when using a different output dir" \{ spago, fixture } -> do
      spago [ "init", "--name", "7368613235362d6a336156536c675a7033334e7659556c6d38" ] >>= shouldBeSuccess

      let tempDir = Path.toRaw $ Paths.paths.temp </> "output"
      spago [ "build", "--output", tempDir ] >>= shouldBeSuccess
      spago [ "test", "--output", tempDir ] >>= shouldBeSuccessOutputWithErr (fixture "test-output-stdout.txt") (fixture "test-output-stderr.txt")

    Spec.it "fails nicely when the test module is not found" \{ spago, fixture, testCwd } -> do
      spago [ "init", "--name", "7368613235362d6a336156536c675a7033334e7659556c6d38" ] >>= shouldBeSuccess
      spago [ "build" ] >>= shouldBeSuccess
      FS.moveSync { dst: testCwd </> "test2", src: testCwd </> "test" }
      spago [ "test" ] >>= shouldBeFailureErr (fixture "test-missing-module.txt")

    Spec.it "runs tests from a sub-package" \{ spago, testCwd } -> do
      let subpackage = testCwd </> "subpackage"
      spago [ "init" ] >>= shouldBeSuccess
      FS.mkdirp (subpackage </> "src")
      FS.mkdirp (subpackage </> "test")
      FS.writeTextFile (subpackage </> "src/Main.purs") (Init.srcMainTemplate "Subpackage.Main")
      FS.writeTextFile (subpackage </> "test/Main.purs") (Init.testMainTemplate "Subpackage.Test.Main")
      FS.writeYamlFile Config.configCodec (subpackage </> "spago.yaml")
        ( Init.defaultConfig
            { name: mkPackageName "subpackage"
            , withWorkspace: Nothing
            , testModuleName: "Subpackage.Test.Main"
            }
        )
      spago [ "test", "-p", "subpackage" ] >>= shouldBeSuccess

    Spec.it "runs tests from a sub-package in the current working directory, not the sub-package's directory" \{ spago, fixture, testCwd } -> do
      let subpackage = testCwd </> "subpackage"
      spago [ "init" ] >>= shouldBeSuccess
      FS.mkdirp (subpackage </> "src")
      FS.mkdirp (subpackage </> "test")
      FS.writeTextFile (subpackage </> "src" </> "Main.purs") (Init.srcMainTemplate "Subpackage.Main")

      -- We write a file into the current working directory.
      -- The subpackage test will read the given file without changing its directory
      -- and log its content as its output.
      let textFilePath = testCwd </> "foo.txt"
      let fileContent = "foo"
      FS.writeTextFile textFilePath fileContent
      FS.copyFile
        { src: fixture "spago-subpackage-test-cwd.purs"
        , dst: subpackage </> "test" </> "Main.purs"
        }
      FS.writeYamlFile Config.configCodec (subpackage </> "spago.yaml")
        ( ( Init.defaultConfig
              { name: mkPackageName "subpackage"
              , withWorkspace: Nothing
              , testModuleName: "Subpackage.Test.Main"
              }
          ) # plusDependencies [ "aff", "node-buffer", "node-fs" ]
        )
      spago [ "test", "-p", "subpackage" ] >>= checkOutputsStr { stdoutStr: Just fileContent, stderrStr: Nothing, result: isRight }

    Spec.it "fails when running tests from a sub-package, where the module does not exist" \{ spago, testCwd } -> do
      let subpackage = testCwd </> "subpackage"
      spago [ "init" ] >>= shouldBeSuccess
      FS.mkdirp (subpackage </> "src")
      FS.mkdirp (subpackage </> "test")
      FS.writeTextFile (subpackage </> "src/Main.purs") (Init.srcMainTemplate "Subpackage.Main")
      FS.writeTextFile (subpackage </> "test/Main.purs") (Init.testMainTemplate "Subpackage.Test.Main2")
      FS.writeYamlFile Config.configCodec (subpackage </> "spago.yaml")
        ( Init.defaultConfig
            { name: mkPackageName "subpackage"
            , withWorkspace: Nothing
            , testModuleName: "Subpackage.Test.Main"
            }
        )
      spago [ "test", "-p", "subpackage" ] >>= shouldBeFailure

    Spec.it "can use a custom output folder" \{ spago, testCwd } -> do
      spago [ "init" ] >>= shouldBeSuccess
      spago [ "test", "--output", "myOutput" ] >>= shouldBeSuccess
      FS.exists (testCwd </> "myOutput") `Assert.shouldReturn` true

    Spec.it "'strict: true' on package src does not cause test code containing warnings to fail to build" \{ spago, testCwd } -> do
      spago [ "init" ] >>= shouldBeSuccess
      -- add --strict
      FS.writeYamlFile Config.configCodec (testCwd </> "spago.yaml") $ Init.defaultConfig' $ PackageAndWorkspace
        { name: mkPackageName "package-a"
        , dependencies: [ "prelude", "effect", "console" ]
        , test: Just { moduleMain: "Test.Main", strict: Nothing, censorTestWarnings: Nothing, pedanticPackages: Nothing, dependencies: Nothing }
        , build: Just { strict: Just true, censorProjectWarnings: Nothing, pedanticPackages: Nothing }
        }
        { setVersion: Just $ unsafeFromRight $ Version.parse "0.0.1" }

      -- add version where test file has warning
      FS.writeTextFile (testCwd </> "test" </> "Test" </> "Main.purs") $ Array.intercalate "\n"
        [ "module Test.Main where"
        , ""
        , "import Prelude"
        , "import Effect (Effect)"
        , "import Effect.Class.Console (log)"
        , "main :: Effect Unit"
        , "main = bar 1"
        , ""
        , "bar :: Int -> Effect Unit"
        , "bar unusedName = do"
        , "  log \"🍕\""
        , "  log \"You should add some tests.\""
        , ""
        ]
      let
        exp =
          case Process.platform of
            Just Platform.Win32 -> "[WARNING 1/1 UnusedName] test\\Test\\Main.purs:10:5"
            _ -> "[WARNING 1/1 UnusedName] test/Test/Main.purs:10:5"
        hasUnusedNameWarningError stdErr = do

          unless (String.contains (String.Pattern exp) stdErr) do
            Assert.fail $ "STDERR did not contain text:\n" <> exp <> "\n\nStderr was:\n" <> stdErr
      spago [ "test" ] >>= check { stdout: mempty, stderr: hasUnusedNameWarningError, result: isRight }
