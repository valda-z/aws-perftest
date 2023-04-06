$rg = 'perftest-rg'
$acrName = 'jjazacrperf'
az group create -n $rg -l SwedenCentral
az deployment group create -g $rg --template-file deploy-acr.bicep --parameters acrName=$acrName

# push image to ACR
az acr build -t perftest:v2 -r $acrName https://github.com/jjindrich/jjazure-perftest.git -f PerfTest\Dockerfile --platform linux