## Automated Test Pipeline Lab

Branched from https://github.com/bstiffler582/NEM_2024_SDT.git

LAB home: https://github.com/BA-Belgium/Lab-Jenkins-TwinCAT-Unit-Tests
 
!REMARK: This lab can only be used with TwinCAT 3.1.4026 since it makes use of a User Mode runtime for the test framework.

!REMARK: The necessary licenses for the framework test must be available in the **UmRt_Default** runtime. The user mode runtime itself is set up by the deployment script.

### Contents

1. [Introduction](#introduction)
2. [Jenkins Prerequisites](#jenkins_prerequisites)
3. [Testing](#testing)
4. [Outro](#outro)

<a id="introduction"></a>

### 1. Introduction

In the industrial automation industry, TwinCAT is uniquely suited for adopting modern software tooling and practices. Requests from customers looking to implement *continuous integration*, *continuous deployment* and *automated testing* with their PLC programs are becoming more and more frequent. The intent of this lab is to illustrate the overall landscape of CI/CD with TwinCAT, as well as to provide a hands-on demonstration of at least one path to realize these workflows with TwinCAT.

<a id="jenkins_prerequisites"></a>

### 2. Jenkins Installation

Use the first lab https://github.com/BA-Belgium/Lab-Jenkins-Build-And-Deploy-Lib as the foundation for this lab to set up and configure Jenkins.

<a id="testing"></a>

### 3. Testing

Automated testing is another topic of the software development conversation that has gained a lot of attention over the past several years from TwinCAT users. Customers with exposure to testing libraries and frameworks for common software languages (C#, JavaScript, python) are hoping to be able to implement similar workflows with their PLC development stacks.

>None of us are strangers to comprehensive testing of our PLC programs. However, the mindset of developing software modules *around* their ability to be tested (often called TDD - Test Driven Development) is a relatively novel strategy - especially for "device-level" programmers like us.

Let's add some automated tests to our TwinCAT project. 

>**Unit Tests** are the easiest to describe and implement, because they test an individual *unit* of code and nothing more. Once multiple modules, components or execution paths become involved, it is no longer a *unit* test, and instead something else.

There are a handful of community-developed unit testing frameworks available for TwinCAT that provide a wide range of features. For ease of demonstration, we will use the bare-bones "test framework" library included in this repository.

Clone or download the library project and add it to your solution.

First, bring in the `TestFramework` library project via **solution -> Add existing item** as a standalone plc project. We will save this project as a library, install it, and set it up as a *Reference project* in TwinCAT. This is a 4026 feature which allows us to use the project as a library, but also directly debug it from the same solution if necessary. 

The TestFramework project contains Function Blocks to make specifying and running tests easier, but most importantly, it will format the ensuing results in a way that Jenkins can digest:

```xml
<testsuite tests="3">
    <testcase classname="foo1" name="ASuccessfulTest"/>
    <testcase classname="foo2" name="AnotherSuccessfulTest"/>
    <testcase classname="foo3" name="AFailingTest">
        <failure type="NotEnoughFoo">Details about failure</failure>
    </testcase>
</testsuite>
```

Now, we just need an application to test. Let's write some simple, testable PLC code. Create a solution and plc project and add the code below, or just use the final solution in the repository.

Create a structure that will act as our "Recipe":
```js
TYPE RecipeData :
STRUCT
	fTemperature        : REAL;
	nAgitatorSpeed      : DINT;
	nMixTimeSecs        : DINT;
END_STRUCT
END_TYPE
```
And then a function which validates the bounds of the recipe values:
```js
FUNCTION ValidateRecipe : BOOL
VAR_INPUT
	Recipe          : REFERENCE TO RecipeData;
END_VAR
VAR
END_VAR
```
```js
ValidateRecipe :=
    (Recipe.fTemperature >= 140.0 AND Recipe.fTemperature <= 185.0) AND
    (Recipe.nAgitatorSpeed >= 10 AND Recipe.nAgitatorSpeed <= 100) AND
    (Recipe.nMixTimeSecs >= 300 AND Recipe.nMixTimeSecs <= 500); 
```
Now we can create some tests to ensure the recipe validation function works as expected. Create a new FB which inherits from the `FB_SimpleTest` block (defined in the library):
```js
FUNCTION_BLOCK FB_RecipeValidTest EXTENDS FB_SimpleTest
VAR_INPUT
	bExpected       : BOOL;
	MockRecipe      : RecipeData := (
                        fTemperature:=140.0, 
                        nAgitatorSpeed:=10, 
                        nMixTimeSecs:=300
                    );
END_VAR
VAR_OUTPUT
END_VAR
VAR
END_VAR
```
We include some initialized mock data to run the test with.
The `Execute` method will actually call our validation function and test the results with an expected value:
```js
METHOD Execute : BOOL
VAR_INPUT
END_VAR
VAR_INST
	bResult		: BOOL;
END_VAR
```
```js
bResult := ValidateRecipe(MockRecipe);
AssertEquals(bExpected, bResult, 'Recipe validation failed');
Execute := TRUE;
```
We will not override any other properties or methods from the base type, so delete the rest of the properties to avoid an error.

We can now use this block to test multiple recipe validation scenarios. Set this up in `MAIN` to account for just a few different cases:
```js
fbRecipeTest_Valid              : FB_RecipeValidTest(sTestName:='Recipe Valid') := 
                                    (bExpected:= TRUE);
fbRecipeTest_InvalidLoTemp      : FB_RecipeValidTest(sTestName:='Recipe Invalid Lo Temp') := 
                                    (bExpected:= FALSE, 
                                    MockRecipe:=(fTemperature:=139.9));
fbRecipeTest_InvalidHiTemp      : FB_RecipeValidTest(sTestName:='Recipe Invalid Hi Temp') := 
                                    (bExpected:= FALSE,
                                    MockRecipe:=(fTemperature:=185.1));
```
All the test setup is taken care of right in the declaration. We just need to instatiate the test runner block and pass our test cases in:
```js
fbTestRunner                    : FB_TestRunner;
bInit                           : BOOL;
```
```js
// run once
IF NOT bInit THEN
    fbTestRunner.AddTest(fbRecipeTest_Valid);
    fbTestRunner.AddTest(fbRecipeTest_InvalidLoTemp);
    fbTestRunner.AddTest(fbRecipeTest_InvalidHiTemp);
    bInit := TRUE;
END_IF
fbTestRunner.Execute();
```
The test runner will handle calling the `Execute` method of our test blocks, and saving off all the results to an XML file on the root the runtime as `testresults.xml`. Feel free to modify the mock data or expected values to force a test failure.

> Be sure to read in the runtime configuration and set appropriately for your local target.

Finally to tie everything together:
- Modify the build script
    - Activate configuration onto a target, in the repository script a UM runtime is created and used
    - run the test framework (a minimalistic script is printed below, see the full script in the repository)
    - Copy the test results output to Jenkins workspace
```ps
$dte = new-object -com "TcXaeShell.DTE.17.0" # XaeShell64 COM ProgId
$dte.SuppressUI = $true # suppress VS interface

# open solution file
echo "Opening solution"
$slnPath = "$pwd\TwinCAT Project\TwinCAT Project.sln"
$sln = $dte.Solution
$sln.Open($slnPath)

echo "Building TwinCAT project"
$sln.SolutionBuild.Build($true)

echo "Activating Configuration"
$systemProject = $sln.Projects.Item(1)
$systemManager = $systemProject.Object
$systemManager.ActivateConfiguration()

echo "Restarting TwinCAT runtime"
$systemManager.StartRestartTwinCAT()

echo "Copying test results"
Start-Sleep 5 # give the test process some time...
Move-Item -Path C:\testresults.xml -Destination $pwd\testresults.xml

echo "Exiting..."
$dte.Quit()
```
- Add one more **Post-build Action** to the Jenkins job:
    - Type *Publish JUnit test result report*
    - *Test report XMLs* value: `testresults.xml`

Commit and push your changes. Either wait for the SCM Poll to trigger the job, or manually initiate it. Watch the output and ensure the test results are moved to the workspace directory. You should now be able to view the results within Jenkins.

<a id="outro"></a>

### 8. Outro

We have demonstrated automating the build and test process of a TwinCAT project using Jenkins, PowerShell and the Automation Interface API. With this exposure, hopefully you have gained familiarity with DevOps tooling and terminologies, as well as the continuous integration workflow. From the TwinCAT perspective, realizing this workflow in other comparable tools (e.g. Azure DevOps) would look very similar.
