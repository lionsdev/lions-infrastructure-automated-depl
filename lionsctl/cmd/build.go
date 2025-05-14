package cmd

import (
	"context"
	"fmt"
	"os"

	"dagger.io/dagger"
	"github.com/lionsdev/lionsctl/lionsctl"
	"github.com/spf13/cobra"
)

// buildCmd represents the build command
var buildCmd = &cobra.Command{
	Use:   "build",
	Short: "Construit une image Docker pour l'application",
	Long: `Construit une image Docker pour l'application et la publie dans la registry LIONS.
Cette commande effectue les étapes suivantes:
1. Clone le dépôt Git de l'application
2. Construit l'application
3. Crée une image Docker
4. Publie l'image dans la registry LIONS`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("build called")

		ctx := context.Background()

		client, err := dagger.Connect(ctx, dagger.WithLogOutput(os.Stdout))
		if err != nil {
			return err
		}

		defer client.Close()

		cloneOptions := lionsctl.CloneOptions{
			GitURL: url,
			Branch: branch,
		}

		repoInfo, err := lionsctl.Clone(ctx, client, &cloneOptions)
		if err != nil {
			return err
		}

		packageOptions := lionsctl.PackageOptions{
			PackageSource: repoInfo.ClonedSource,
			Profile:       profile,
			Define:        define,
			JavaVersion:   javaVersion,
		}

		buildDir, err := lionsctl.Package(ctx, client, &packageOptions)
		if err != nil {
			return err
		}

		appName, err := lionsctl.AppName(url)
		if err != nil {
			return err
		}

		buildOptions := lionsctl.BuildOptions{
			DockerContext: buildDir,
			AppName:       appName,
			Tag:           repoInfo.BranchDigest,
		}

		err = lionsctl.Build(ctx, client, &buildOptions)
		if err != nil {
			return err
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(buildCmd)

	buildCmd.Flags().StringVarP(&url, "url", "u", "", "application git repository url: eg -u https://github.com/lionsdev/my-application")
	buildCmd.MarkFlagRequired("url")
	buildCmd.Flags().StringVarP(&branch, "branch", "b", lionsctl.GIT_DEFAULT_BRANCH, "git branch: eg: -b main ")
	buildCmd.Flags().StringVarP(&profile, "profile", "p", "", "define maven profile: eg: -p dev ")
	buildCmd.Flags().StringSliceVarP(&define, "define", "d", []string{}, "define maven properties: eg: -d quarkus.profile=dev ")
	buildCmd.Flags().Int16VarP(&javaVersion, "java-version", "j", 11, "la version du jdk 11 ou 17")
}