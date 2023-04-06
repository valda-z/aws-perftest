$rg = 'perftest-rg'
az group create -n $rg -l SwedenCentral
az deployment group create -g $rg --template-file deploy-aca.bicep