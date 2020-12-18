import naming

def GenerateConfig(context):
    license = 'hourly-pricing'

    config={}
    config['resources'] = []
    config['outputs'] = []

    clusters = GetClusters(context)

    deployment = {
        'name': 'deployment',
        'type': 'deployment.py',
        'properties': {
            'syncGatewayVersion': context.properties['syncGatewayVersion'],
            'couchbaseUsername': context.properties['couchbaseUsername'],
            'couchbasePassword': context.properties['couchbasePassword'],
            'couchbaseConnectionstring': context.properties['couchbaseConnectionstring'],
            'couchbaseBucketName': context.properties['couchbaseBucketName'],
            'license': license,
            'clusters': clusters
        }
    }
    config['resources'].append(deployment)

    for cluster in clusters:
        clusterName = cluster['cluster']
        for group in cluster['groups']:
            outputName = naming.ExternalIpOutputName(clusterName, group['group'])
            config['outputs'].append({
                'name': outputName,
                'value': '$(ref.deployment.%s)' % outputName
            })

    return config

def GetClusters(context):
    clusters = []
    regions = GetRegionsList(context)
    for region in regions:
        cluster = {
            'cluster': region,
            'region': region,
            'groups': [ ]
        }
        if context.properties['syncGatewayNodeCount']>0:
            cluster['groups'].append({
                'group': 'syncgateway',
                'diskSize': context.properties['syncGatewayDiskSize'],
                'nodeCount': context.properties['syncGatewayNodeCount'],
                'nodeType': context.properties['syncGatewayNodeType'],
                'couchbaseUsername': context.properties['couchbaseUsername'],
                'couchbasePassword': context.properties['couchbasePassword'],
                'couchbaseConnectionstring': context.properties['couchbaseConnectionstring'],
                'couchbaseBucketName': context.properties['couchbaseBucketName'],
                'services': ['syncGateway']
            })
        clusters.append(cluster)
    return clusters

def GetRegionsList(context):
    regions = []
    availableRegions = [
        'us-central1',
        'us-west1',
        'us-east1',
        'us-east4',
        'europe-west1',
        'europe-west2',
        'europe-west3',
        'asia-southeast1',
        'asia-east1',
        'asia-northeast1',
        'australia-southeast1'
    ]
    for region in availableRegions:
        if context.properties[region]:
            regions.append(region)
    return regions

def GeneratePassword():
    import random
    categories = ['ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '123456789', '*-+.']
    password=[]
    for category in categories:
        password.insert(random.randint(0, len(password)), random.choice(category))
    while len(password) < 8:
        password.insert(random.randint(0, len(password)), random.choice(''.join(categories)))
    return ''.join(password)
