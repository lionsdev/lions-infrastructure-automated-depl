package cmd

import (
	"context"
	"fmt"
	"os"

	"dagger.io/dagger"
	"github.com/lionsdev/lionsctl/lionsctl"
	"github.com/spf13/cobra"
)

// deployCmd represents the deploy command
var deployCmd = &cobra.Command{
	Use:   "deploy",
	Short: "Déploie une application sur Kubernetes",
	Long: `Déploie une application sur Kubernetes en utilisant Helm.
Cette commande met à jour le tag de l'image dans les fichiers de configuration et déploie l'application.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("deploy called")

		ctx := context.Background()

		client, err := dagger.Connect(ctx, dagger.WithLogOutput(os.Stdout))
		if err != nil {
			return err
		}

		defer client.Close()

		configUrl, err := lionsctl.ConfigUrl(name, cluster)
		if err != nil {
			return err
		}

		deployOptions := lionsctl.DeployOptions{
			ConfigURL:   configUrl,
			AppName:     name,
			Cluster:     lionsctl.Cluster(cluster),
			Environment: environment,
		}

		err = lionsctl.Deploy(ctx, client, deployOptions)
		if err != nil {
			return err
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(deployCmd)

	deployCmd.Flags().StringVarP(&name, "name", "n", "", "application name: eg -n my-application")
	deployCmd.MarkFlagRequired("name")
	deployCmd.Flags().StringVarP(&environment, "environment", "e", "development", "le nom de l'environment: eg -e development")
	deployCmd.MarkFlagRequired("environment")
	deployCmd.Flags().StringVarP(&cluster, "cluster", "c", "k2", "k8s cluster k1 or k2")
	deployCmd.MarkFlagRequired("cluster")
}