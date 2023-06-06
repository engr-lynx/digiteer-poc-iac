# Deploy project
yarn
npx yaml2json cdk.context.yaml > cdk.context.json
cdk deploy --require-approval never
