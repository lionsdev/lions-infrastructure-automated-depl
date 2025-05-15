package sigctlv2

import (
	"context"
	"fmt"
	"os"

	"dagger.io/dagger"
)

// const MAVEN_IMAGE = "maven:3.9.1-eclipse-temurin-17"
// const MAVEN_SIGOBE_IMAGE = "dcr.dgbf.ci/maven-sigobe:3.6.3-openjdk-11-v0.0.2"
const MAVEN_SIGOBE_IMAGE_JDK17 = "dcr.dgbf.ci/maven:3.8.5-openjdk-17-v0.0.12"
const MAVEN_SIGOBE_IMAGE_JDK11 = "dcr.dgbf.ci/maven:3.8.5-openjdk-11-v0.0.12"
const MAVEN_SOURCE_DIR = "/source"
const MAVEN_CACHE_KEY = "maven"
const MAVEN_REPO_DIR = "/root/.m2/repository"
const MAVEN_SIGOBE_LIB_DIR = "/root/library/"

type PackageOptions struct {
	PackageSource string
	Profile       string
	Define        []string
	AppName       string
	JavaVersion   int16
}

func Package(ctx context.Context, client *dagger.Client, opts *PackageOptions) (buildDir string, err error) {

	source := client.Host().Directory(opts.PackageSource)
	cacheVolume := client.CacheVolume(MAVEN_CACHE_KEY)

	builder := client.Container().From(javaVersion(opts.JavaVersion)).
		WithMountedCache(MAVEN_REPO_DIR, cacheVolume).
		WithWorkdir(MAVEN_SIGOBE_LIB_DIR).
		WithExec([]string{"mvn", "install:install-file",
			"-Dfile=/root/library/atlantis-2.0.0.jar",
			"-DgroupId=org.primefaces.themes",
			"-DartifactId=atlantis",
			"-Dversion=2.0.0",
			"-Dpackaging=jar",
			"-DlocalRepositoryPath=/root/.m2/repository",
		}).WithExec([]string{"mvn", "install:install-file",
		"-Dfile=/root/library/sib-menu-generator-1.0.8.jar",
		"-DgroupId=ci.gouv.dgbf",
		"-DartifactId=sib-menu-generator",
		"-Dversion=1.0.8",
		"-Dpackaging=jar",
		"-DlocalRepositoryPath=/root/.m2/repository",
	}).WithExec([]string{"mvn", "install:install-file",
		"-Dfile=/root/library/sib-menu-generator-1.0.6.jar",
		"-DgroupId=ci.gouv.dgbf",
		"-DartifactId=sib-menu-generator",
		"-Dversion=1.0.6",
		"-Dpackaging=jar",
		"-DlocalRepositoryPath=/root/.m2/repository",
	}).WithExec([]string{"mvn", "install:install-file",
		"-Dfile=/root/library/sib-menu-generator-1.0.6.jar",
		"-DgroupId=ci.gouv.dgbf",
		"-DartifactId=sib-menu-generator",
		"-Dversion=1.0.6",
		"-Dpackaging=jar",
		"-DlocalRepositoryPath=/root/.m2/repository",
	}).WithExec([]string{"mvn", "install:install-file",
		"-Dfile=/root/library/sib-menu-generator-1.10.0.jar",
		"-DgroupId=ci.gouv.dgbf",
		"-DartifactId=sib-menu-generator",
		"-Dversion=1.10.0",
		"-Dpackaging=jar",
		"-DlocalRepositoryPath=/root/.m2/repository",
	}).WithExec([]string{"mvn", "install:install-file",
		"-Dfile=/root/library/sib-menu-generator-fa-1.10.2.jar",
		"-DgroupId=ci.gouv.dgbf",
		"-DartifactId=sib-menu-generator-fa",
		"-Dversion=fa-1.10.2",
		"-Dpackaging=jar",
		"-DlocalRepositoryPath=/root/.m2/repository",
	}).WithExec([]string{"mvn", "install:install-file",
		"-Dfile=/root/library/sib-menu-generator-fa-1.10.2.jar",
		"-DgroupId=ci.gouv.dgbf",
		"-DartifactId=sib-menu-generator-fa",
		"-Dversion=1.10.2",
		"-Dpackaging=jar",
		"-DlocalRepositoryPath=/root/.m2/repository",
	}).WithExec([]string{"mvn", "install:install-file",
		"-Dfile=/root/library/quantum-functional-1.0.jar",
		"-DgroupId=quantum",
		"-DartifactId=quantum-functional",
		"-Dversion=1.0",
		"-Dpackaging=jar",
		"-DlocalRepositoryPath=/root/.m2/repository"})

	builder = builder.WithDirectory(MAVEN_SOURCE_DIR, source).
		WithMountedCache(MAVEN_REPO_DIR, cacheVolume).
		WithWorkdir(MAVEN_SOURCE_DIR).
		WithExec([]string{"mvn", "-version"}).
		WithExec(mvnBuildCmd(opts.Profile, opts.Define)).
		WithExec([]string{"ls", "-al", MAVEN_SOURCE_DIR + "/target"})

	/*
		builder = client.Container().From(javaVersion(opts.JavaVersion)).
			WithDirectory(MAVEN_SOURCE_DIR, source).
			WithMountedCache(MAVEN_REPO_DIR, cacheVolume).
			WithWorkdir(MAVEN_SOURCE_DIR).
			WithExec([]string{"mvn", "-version"}).
			WithExec(mvnBuildCmd(opts.Profile, opts.Define)).
			WithExec([]string{"ls", "-al", MAVEN_SOURCE_DIR + "/target"})
	*/

	if err != nil {
		return "", err
	}

	out, err := builder.Stdout(ctx)
	if err != nil {
		return "", err
	}

	fmt.Print(out)

	buildDir, err = os.MkdirTemp("", "build")
	if err != nil {
		return "", nil
	}

	//export build result to host
	output := builder.Directory(MAVEN_SOURCE_DIR)
	_, err = output.Export(ctx, buildDir)
	if err != nil {
		return "", err
	}

	fmt.Printf("---BUILD DIR: %s\n", buildDir)

	return buildDir, nil
}

func mvnBuildCmd(profile string, properties []string) []string {

	params := []string{}

	params = append(params, "mvn", "clean", "package")

	if profile != "" {
		profile = "-P" + profile
		params = append(params, profile)
	}

	if len(properties) != 0 {
		for _, v := range properties {
			val := "-D" + v
			params = append(params, val)
		}
	}

	fmt.Printf("--maven command: %s", params)

	return params
}

func javaVersion(version int16) string {
	fmt.Printf("--JAVA VERSION: %d\n", version)
	switch version {
	case 11:
		return MAVEN_SIGOBE_IMAGE_JDK11
	case 17:
		return MAVEN_SIGOBE_IMAGE_JDK17
	default:
		return MAVEN_SIGOBE_IMAGE_JDK11
	}

}
