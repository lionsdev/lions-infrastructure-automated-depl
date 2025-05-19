package cmd

import (
	"context"
	"fmt"
	"os"

	"dagger.io/dagger"
	"github.com/lionsdev/lionsctl/lionsctl"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

// initCmd represents the init command
var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialise une nouvelle application dans l'infrastructure LIONS",
	Long: `Initialise une nouvelle application dans l'infrastructure LIONS en créant:
- Un dépôt Git pour la configuration
- Des templates Kubernetes (Helm charts)
- Une configuration d'ingress (optionnelle)
- Une configuration de volume persistant (optionnelle)`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("init called")

		client, err := dagger.Connect(context.Background(), dagger.WithLogOutput(os.Stdout))
		if err != nil {
			return err
		}

		defer client.Close()

		ctx := context.Background()

		opts := lionsctl.NewCreateGitRepoOtions(name, cluster, viper.GetString("GIT.CFG_DEFAULT_BRNCH"), false)
		err = lionsctl.CreateConfig(context.Background(), client, &opts)
		if err != nil {
			return err
		}

		iopts := lionsctl.InitRepoOptions{
			Ingress:     ingress,
			Volume:      volume,
			AppName:     name,
			Cluster:     cluster,
			Environment: environment,
		}

		err = lionsctl.InitRepo(ctx, client, iopts)
		if err != nil {
			return err
		}

		return nil

	},
}

func init() {
	rootCmd.AddCommand(initCmd)

	initCmd.Flags().StringVarP(&name, "name", "n", "", "application name: eg -n my-application")
	initCmd.MarkFlagRequired("name")
	initCmd.Flags().StringVarP(&cluster, "cluster", "c", "k2", "le cluster kubernetes k1 ou k2")
	initCmd.MarkFlagRequired("cluster")
	initCmd.Flags().StringVarP(&environment, "environment", "e", "development", "environnement cible (development, staging, production)")
	initCmd.Flags().BoolVarP(&ingress, "ingress", "i", false, "application avec ingress: eg -i true")
	initCmd.Flags().BoolVarP(&volume, "volume", "v", false, "application avec volume en Gi: eg -v true")
}
