az group create -n perftest-rg -l SwedenCentral
az deployment group create -g perftest-rg --template-file deploy-aca.bicep