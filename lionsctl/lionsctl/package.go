package lionsctl

import (
	"context"
	"fmt"
	"log"
	"os"
	"path"
	"strings"

	"dagger.io/dagger"
)

type PackageOptions struct {
	PackageSource *dagger.Directory
	Profile       string
	Define        []string
	JavaVersion   int16
}

func Package(ctx context.Context, client *dagger.Client, opts *PackageOptions) (*dagger.Directory, error) {

	fmt.Println("--- PACKAGE APPLICATION")

	buildDir, err := os.MkdirTemp("", "build")
	if err != nil {
		return nil, err
	}
	log.Printf("---BUILD TEMP DIR: %s", buildDir)

	buildDirHost := client.Host().Directory(buildDir)

	mavenImage := fmt.Sprintf("maven:3.9.0-eclipse-temurin-%d", opts.JavaVersion)
	log.Printf("---MAVEN IMAGE: %s", mavenImage)

	mavenContainer := client.Container().
		From(mavenImage).
		WithMountedDirectory("/src", opts.PackageSource).
		WithWorkdir("/src")

	if hasPom(ctx, opts.PackageSource) {
		log.Println("--- MAVEN PROJECT")

		mavenArgs := []string{"clean", "package", "-DskipTests"}

		if opts.Profile != "" {
			mavenArgs = append(mavenArgs, fmt.Sprintf("-P%s", opts.Profile))
		}

		for _, define := range opts.Define {
			mavenArgs = append(mavenArgs, fmt.Sprintf("-D%s", define))
		}

		log.Printf("--- MAVEN ARGS: %v", mavenArgs)

		mavenContainer = mavenContainer.WithExec(mavenArgs)

		targetDir := mavenContainer.Directory("/src/target")

		jarFiles, err := findJarFiles(ctx, targetDir)
		if err != nil {
			return nil, err
		}

		if len(jarFiles) == 0 {
			return nil, fmt.Errorf("no jar files found in target directory")
		}

		log.Printf("--- JAR FILES: %v", jarFiles)

		jarFile := jarFiles[0]
		log.Printf("--- JAR FILE: %s", jarFile)

		jarPath := path.Join("/src/target", jarFile)
		log.Printf("--- JAR PATH: %s", jarPath)

		dockerfilePath := path.Join(buildDir, "Dockerfile")
		log.Printf("--- DOCKERFILE PATH: %s", dockerfilePath)

		err = createDockerfile(dockerfilePath, jarFile, opts.JavaVersion)
		if err != nil {
			return nil, err
		}

		_, err = mavenContainer.WithExec([]string{"cp", jarPath, "/src"}).
			WithExec([]string{"ls", "-la", "/src"}).
			WithExec([]string{"cp", jarPath, "/src/app.jar"}).
			WithExec([]string{"ls", "-la", "/src"}).
			File("/src/app.jar").Export(ctx, path.Join(buildDir, "app.jar"))
		if err != nil {
			return nil, err
		}

		return buildDirHost, nil
	}

	if hasPackageJson(ctx, opts.PackageSource) {
		log.Println("--- NODE PROJECT")

		nodeContainer := client.Container().
			From("node:18-alpine").
			WithMountedDirectory("/src", opts.PackageSource).
			WithWorkdir("/src").
			WithExec([]string{"npm", "install"}).
			WithExec([]string{"npm", "run", "build"})

		buildOutput := nodeContainer.Directory("/src/build")

		dockerfilePath := path.Join(buildDir, "Dockerfile")
		log.Printf("--- DOCKERFILE PATH: %s", dockerfilePath)

		err = createNodeDockerfile(dockerfilePath)
		if err != nil {
			return nil, err
		}

		_, err = buildOutput.Export(ctx, path.Join(buildDir, "build"))
		if err != nil {
			return nil, err
		}

		return buildDirHost, nil
	}

	return nil, fmt.Errorf("unsupported project type")
}

func hasPom(ctx context.Context, dir *dagger.Directory) bool {
	_, err := dir.File("pom.xml").ID(ctx)
	return err == nil
}

func hasPackageJson(ctx context.Context, dir *dagger.Directory) bool {
	_, err := dir.File("package.json").ID(ctx)
	return err == nil
}

func findJarFiles(ctx context.Context, dir *dagger.Directory) ([]string, error) {
	entries, err := dir.Entries(ctx)
	if err != nil {
		return nil, err
	}

	var jarFiles []string
	for _, entry := range entries {
		if strings.HasSuffix(entry, ".jar") && !strings.Contains(entry, "sources") && !strings.Contains(entry, "javadoc") {
			jarFiles = append(jarFiles, entry)
		}
	}

	return jarFiles, nil
}

func createDockerfile(dockerfilePath string, jarFile string, javaVersion int16) error {
	dockerfile := fmt.Sprintf(`FROM eclipse-temurin:%d-jre-alpine
WORKDIR /app
COPY app.jar /app/app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
`, javaVersion)

	return os.WriteFile(dockerfilePath, []byte(dockerfile), 0644)
}

func createNodeDockerfile(dockerfilePath string) error {
	dockerfile := `FROM nginx:alpine
COPY build /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]`

	return os.WriteFile(dockerfilePath, []byte(dockerfile), 0644)
}
