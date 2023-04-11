$rg = 'perftest-rg'
az group create -n $rg -l SwedenCentral
az deployment group create -g $rg --template-file deploy-aca.bicep

# check replica count
az containerapp replica list -g $rg -n jjazacaperf -o table