#!/bin/bash
# COMPLETE ALL-IN-ONE SETUP SCRIPT WITH FIXES
# This script does EVERYTHING: cleanup, fixes, venv setup, configuration, and starts services
# Just run: ./complete_setup_fixed.sh

set -e  # Exit on any error

PROJECT_NAME="podman-dev-stack"
VENV_NAME="venv"

echo "🚀 COMPLETE ALL-IN-ONE PODMAN DEVELOPMENT STACK SETUP"
echo "====================================================="
echo "This script will:"
echo "  • Clean up any existing setup"
echo "  • Fix Airflow image issues" 
echo "  • Create Python virtual environment"
echo "  • Install all packages"
echo "  • Create all configuration files"
echo "  • Start all services"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# =============================================================================
# STEP 1: CLEANUP AND PREPARATION
# =============================================================================

echo ""
echo "🧹 CLEANUP: Removing existing containers and setup..."

# Stop and remove any existing containers
podman stop podman-dev-stack_postgres_1 podman-dev-stack_localstack_1 podman-dev-stack_openwebui_1 2>/dev/null || true
podman stop podman-dev-stack_airflow-init_1 podman-dev-stack_airflow-webserver_1 2>/dev/null || true
podman rm podman-dev-stack_postgres_1 podman-dev-stack_localstack_1 podman-dev-stack_openwebui_1 2>/dev/null || true
podman rm podman-dev-stack_airflow-init_1 podman-dev-stack_airflow-webserver_1 2>/dev/null || true

# Clean up any existing compose project
podman-compose down -v 2>/dev/null || true

# Remove volumes if they exist
podman volume rm podman-dev-stack_postgres_data podman-dev-stack_localstack_data podman-dev-stack_openwebui_data 2>/dev/null || true

# Clean up system
podman container prune -f 2>/dev/null || true
podman image prune -f 2>/dev/null || true

echo "✅ Cleanup completed"

# =============================================================================
# STEP 2: PROJECT AND VIRTUAL ENVIRONMENT SETUP
# =============================================================================

echo ""
echo "📁 Creating project directory and virtual environment..."

# Create project directory
mkdir -p ~/$PROJECT_NAME && cd ~/$PROJECT_NAME
echo "📍 Working in: $(pwd)"

# Check Python
if ! command -v python &> /dev/null; then
    echo "❌ Python is not installed. Please install Python 3.8+ first."
    exit 1
fi

python_version=$(python --version 2>&1 | cut -d' ' -f2)
echo "✅ Found Python $python_version"

# Create virtual environment
echo "🐍 Creating Python virtual environment..."
if [ -d "$VENV_NAME" ]; then
    rm -rf $VENV_NAME
fi
python -m venv $VENV_NAME
source $VENV_NAME/Scripts/activate

echo "✅ Virtual environment activated: $VIRTUAL_ENV"

# Upgrade pip and install packages
echo "📦 Installing Python packages..."
python -m pip install --upgrade pip
pip install \
    podman-compose==1.0.6 \
    awscli-local \
    boto3 \
    opensearch-py \
    psycopg2-binary \
    requests \
    pyyaml

echo "✅ Packages installed:"
pip list | grep -E "(podman-compose|awscli-local|boto3|opensearch|psycopg2)"

# =============================================================================
# STEP 3: FIND WORKING AIRFLOW IMAGE
# =============================================================================

echo ""
echo "🔍 Finding working Airflow image..."

# Test available Airflow images
AIRFLOW_IMAGES=(
    "apache/airflow:2.8.1"
    "apache/airflow:2.9.0" 
    "apache/airflow:2.9.1"
    "apache/airflow:2.8.0"
    "apache/airflow:slim-2.8.1"
    "apache/airflow:slim-2.9.0"
    "apache/airflow:latest"
)

WORKING_IMAGE=""
for image in "${AIRFLOW_IMAGES[@]}"; do
    echo "Testing: $image"
    if podman pull "$image" > /dev/null 2>&1; then
        echo "  ✅ $image - Available"
        if [ -z "$WORKING_IMAGE" ]; then
            WORKING_IMAGE="$image"
        fi
        break
    else
        echo "  ❌ $image - Not available"
    fi
done

if [ -z "$WORKING_IMAGE" ]; then
    echo "❌ No working Airflow image found. Exiting."
    exit 1
fi

echo ""
echo "🎯 Using Airflow image: $WORKING_IMAGE"

# =============================================================================
# STEP 4: CREATE PROJECT STRUCTURE
# =============================================================================

echo ""
echo "📂 Creating project structure..."
mkdir -p airflow/{dags,logs,config,plugins}
mkdir -p localstack/init
mkdir -p scripts data
chmod -R 755 airflow/

# =============================================================================
# STEP 5: CREATE CONFIGURATION FILES
# =============================================================================

echo "📝 Creating podman-compose.yml with working image..."
cat > podman-compose.yml << EOF
version: '3.8'

x-airflow-common:
  &airflow-common
  image: $WORKING_IMAGE
  environment: &airflow-common-env
    AIRFLOW__CORE__EXECUTOR: LocalExecutor
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:airflow@postgres/airflow
    AIRFLOW__CORE__FERNET_KEY: 'YlCImzjge_TeZc4RjDgMz7Culg5gIHTgXWIvdWS7y1s='
    AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION: 'true'
    AIRFLOW__CORE__LOAD_EXAMPLES: 'false'  
    AIRFLOW__API__AUTH_BACKENDS: 'airflow.api.auth.backend.basic_auth,airflow.api.auth.backend.session'
    AIRFLOW__SCHEDULER__ENABLE_HEALTH_CHECK: 'true'
    AIRFLOW__WEBSERVER__EXPOSE_CONFIG: 'true'
    AWS_ACCESS_KEY_ID: test
    AWS_SECRET_ACCESS_KEY: test
    AWS_DEFAULT_REGION: us-east-1
    AWS_ENDPOINT_URL: http://localstack:4566
    _PIP_ADDITIONAL_REQUIREMENTS: boto3 awscli-local opensearch-py psycopg2-binary
  volumes:
    - ./airflow/dags:/opt/airflow/dags
    - ./airflow/logs:/opt/airflow/logs
    - ./airflow/config:/opt/airflow/config
    - ./airflow/plugins:/opt/airflow/plugins
  user: "\${AIRFLOW_UID:-50000}:0"
  depends_on: &airflow-common-depends-on
    postgres:
      condition: service_healthy
  networks:
    - app-network

services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_USER: airflow
      POSTGRES_PASSWORD: airflow  
      POSTGRES_DB: airflow
      POSTGRES_INITDB_ARGS: "--encoding=UTF-8"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "airflow"]
      interval: 10s
      retries: 5
      start_period: 5s
    restart: always
    networks:
      - app-network

  localstack:
    image: localstack/localstack:3.0
    ports:
      - "4566:4566"
      - "4510-4559:4510-4559"
    environment:
      - DEBUG=1
      - SERVICES=s3,redshift,opensearch,logs,iam,sts
      - DATA_DIR=/var/lib/localstack/data
      - LOCALSTACK_HOST=localstack
      - EDGE_PORT=4566
      - AWS_DEFAULT_REGION=us-east-1
      - AWS_ACCESS_KEY_ID=test
      - AWS_SECRET_ACCESS_KEY=test
      - S3_SKIP_SIGNATURE_VALIDATION=1
      - OPENSEARCH_ENDPOINT_STRATEGY=port
      - OPENSEARCH_PORT_EXTERNAL=4511
      - REDSHIFT_PORT_EXTERNAL=4510
      - ES_ENDPOINT_STRATEGY=port
      - ES_PORT_EXTERNAL=4512
    volumes:
      - localstack_data:/var/lib/localstack
      - ./localstack/init:/etc/localstack/init/ready.d
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4566/_localstack/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    restart: always
    networks:
      - app-network

  airflow-webserver:
    <<: *airflow-common
    command: webserver
    ports:
      - "8080:8080"
    environment:
      <<: *airflow-common-env
      AIRFLOW__SCHEDULER__DAG_DIR_LIST_INTERVAL: 30
      AIRFLOW__CORE__LOAD_EXAMPLES: 'false'
      AIRFLOW__WEBSERVER__ENABLE_PROXY_FIX: 'true'
    healthcheck:
      test: ["CMD", "curl", "--fail", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
    restart: always
    depends_on:
      <<: *airflow-common-depends-on
      airflow-init:
        condition: service_completed_successfully



  airflow-init:
    <<: *airflow-common
    entrypoint: /bin/bash
    command:
      - -c
      - |
        mkdir -p /sources/logs /sources/dags /sources/plugins
        chown -R "\${AIRFLOW_UID}:0" /sources/{logs,dags,plugins}
        exec /entrypoint airflow version
        airflow db init
        airflow users create \
          --username admin \
          --firstname Admin \
          --lastname User \
          --role Admin \
          --email admin@example.com \
          --password admin
    environment:
      <<: *airflow-common-env
      _AIRFLOW_DB_MIGRATE: 'true'
      _AIRFLOW_WWW_USER_CREATE: 'true'
      _AIRFLOW_WWW_USER_USERNAME: admin
      _AIRFLOW_WWW_USER_PASSWORD: admin
    user: "0:0"
    volumes:
      - ./airflow:/sources

  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    ports:
      - "3000:8080"
    environment:
      - WEBUI_SECRET_KEY=secretkey123
      - ENABLE_SIGNUP=true
      - DEFAULT_USER_ROLE=user
      - WEBUI_AUTH=true
      - ENABLE_MODEL_FILTER=true
      - MODEL_FILTER_LIST=gpt-3.5-turbo;gpt-4;claude-3
    volumes:
      - openwebui_data:/app/backend/data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
    restart: always
    networks:
      - app-network

volumes:
  postgres_data:
  localstack_data:
  openwebui_data:

networks:
  app-network:
    driver: bridge
EOF

echo "✅ Created podman-compose.yml with image: $WORKING_IMAGE"

# =============================================================================
# STEP 6: CREATE LOCALSTACK INITIALIZATION
# =============================================================================

echo "📝 Creating LocalStack initialization script..."
cat > localstack/init/01-setup-services.sh << 'EOF'
#!/bin/bash
echo "🔧 LocalStack: Setting up services..."
sleep 20

echo "📦 Creating S3 buckets..."
awslocal s3 mb s3://airflow-bucket || true
awslocal s3 mb s3://data-lake-bucket || true
awslocal s3 mb s3://backup-bucket || true

echo "🗄️ Created S3 buckets:"
awslocal s3 ls

echo "👤 Creating IAM user..."
awslocal iam create-user --user-name airflow-user || true
awslocal iam create-access-key --user-name airflow-user || true

echo "🔴 Creating Redshift cluster..."
awslocal redshift create-cluster \
    --cluster-identifier test-cluster \
    --db-name testdb \
    --master-username admin \
    --master-user-password admin123 \
    --node-type dc2.large \
    --cluster-type single-node || true

echo "🔍 Creating OpenSearch domain..."
awslocal opensearch create-domain \
    --domain-name test-domain \
    --elasticsearch-version OpenSearch_1.3 || true

# Wait a bit for OpenSearch to initialize
sleep 10

echo "🔍 Testing OpenSearch endpoint..."
curl -s "http://localhost:4566/test-domain/_cluster/health" || echo "OpenSearch still initializing..."

echo "✅ LocalStack services setup completed!"
echo "📊 Service Summary:"
echo "   S3 Buckets: \$(awslocal s3 ls | wc -l)"
echo "   Redshift: \$(awslocal redshift describe-clusters --query 'Clusters[*].ClusterIdentifier' --output text 2>/dev/null || echo 'Initializing...')"
echo "   OpenSearch: \$(awslocal opensearch list-domain-names --query 'DomainNames[*].DomainName' --output text 2>/dev/null || echo 'Initializing...')"
echo "   OpenSearch Health: \$(curl -s 'http://localhost:4566/test-domain/_cluster/health' | grep -o '\"status\":\"[^\"]*\"' 2>/dev/null || echo 'Initializing...')"
EOF

chmod +x localstack/init/01-setup-services.sh

# =============================================================================
# STEP 7: CREATE SAMPLE DAGS
# =============================================================================

echo "📝 Creating sample Airflow DAGs..."

cat > airflow/dags/local_testing_dag.py << 'EOF'
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
import os
import sys

default_args = {
    'owner': 'admin',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,  
    'retry_delay': timedelta(minutes=5),
}

def test_local_setup():
    """Test the local testing setup with LocalExecutor"""
    print("🏠 Local Testing Setup with LocalExecutor")
    print(f"   Python: {sys.version}")
    print(f"   Executor: LocalExecutor (no separate scheduler needed)")
    print(f"   Virtual env: {os.environ.get('VIRTUAL_ENV', 'Not detected')}")
    print("🌍 AWS LocalStack Environment:")
    print(f"   AWS_ACCESS_KEY_ID: {os.environ.get('AWS_ACCESS_KEY_ID')}")
    print(f"   AWS_DEFAULT_REGION: {os.environ.get('AWS_DEFAULT_REGION')}")
    print(f"   AWS_ENDPOINT_URL: {os.environ.get('AWS_ENDPOINT_URL')}")
    
    # Test imports
    packages = ['boto3', 'opensearchpy', 'psycopg2']
    for pkg in packages:
        try:
            __import__(pkg)
            print(f"✅ {pkg} available")
        except ImportError:
            print(f"❌ {pkg} not available")
    
    return "Local testing setup verified!"

def test_localstack_services():
    """Test LocalStack services: S3, Redshift, and OpenSearch for local development"""
    import boto3
    
    print("🧪 Testing LocalStack Services: S3, Redshift, OpenSearch...")
    results = {}
    
    # Test S3
    try:
        print("📦 Testing S3...")
        s3_client = boto3.client(
            's3',
            endpoint_url='http://localstack:4566',
            aws_access_key_id='test',
            aws_secret_access_key='test',
            region_name='us-east-1'
        )
        
        response = s3_client.list_buckets()
        buckets = [bucket['Name'] for bucket in response['Buckets']]
        print(f"✅ S3 Buckets: {buckets}")
        
        # Test S3 upload
        test_content = "Local Development Test with LocalExecutor!"
        s3_client.put_object(
            Bucket='airflow-bucket',
            Key='local-dev-test.txt',
            Body=test_content.encode('utf-8')
        )
        print("✅ S3 upload test successful")
        results['S3'] = 'Working'
        
    except Exception as e:
        print(f"❌ S3 test failed: {e}")
        results['S3'] = f'Failed: {e}'
    
    # Test Redshift
    try:
        print("🔴 Testing Redshift...")
        import psycopg2
        
        conn = psycopg2.connect(
            host='localstack',
            port=4566,
            user='admin',
            password='admin123',
            database='testdb'
        )
        
        cursor = conn.cursor()
        cursor.execute("SELECT version();")
        version = cursor.fetchone()
        print(f"✅ Redshift connected: {version[0][:50]}...")
        
        # Test table creation
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS test_local_table (
                id INTEGER,
                name VARCHAR(50),
                test_date DATE
            );
        """)
        
        cursor.execute("""
            INSERT INTO test_local_table VALUES 
            (1, 'Local Test 1', '2024-01-01'),
            (2, 'Local Test 2', '2024-01-02');
        """)
        
        cursor.execute("SELECT COUNT(*) FROM test_local_table;")
        count = cursor.fetchone()[0]
        print(f"✅ Redshift table test: {count} rows")
        
        conn.commit()
        cursor.close()
        conn.close()
        results['Redshift'] = 'Working'
        
    except Exception as e:
        print(f"❌ Redshift test failed: {e}")
        results['Redshift'] = f'Failed: {e}'
    
    # Test OpenSearch
    try:
        print("🔍 Testing OpenSearch...")
        from opensearchpy import OpenSearch
        
        client = OpenSearch(
            hosts=[{'host': 'localstack', 'port': 4566}],
            http_auth=('admin', 'admin'),
            use_ssl=False,
            verify_certs=False,
            ssl_assert_hostname=False,
            ssl_show_warn=False,
        )
        
        # Test cluster health
        health = client.cluster.health()
        print(f"✅ OpenSearch cluster status: {health.get('status', 'unknown')}")
        
        # Create test index and document
        index_name = 'local-test-index'
        
        doc = {
            'timestamp': datetime.now().isoformat(),
            'message': 'Local development test with LocalExecutor',
            'source': 'airflow-local',
            'level': 'INFO',
            'service': 'opensearch-test'
        }
        
        client.index(index=index_name, id=1, body=doc)
        print("✅ OpenSearch document indexed")
        
        # Test search
        search_body = {'query': {'match': {'level': 'INFO'}}}
        response = client.search(index=index_name, body=search_body)
        hits = response['hits']['total']['value']
        print(f"✅ OpenSearch search test: {hits} documents found")
        
        results['OpenSearch'] = 'Working'
        
    except Exception as e:
        print(f"❌ OpenSearch test failed: {e}")
        results['OpenSearch'] = f'Failed: {e}'
    
    # Summary
    print("\n📊 LocalStack Services Test Summary:")
    for service, status in results.items():
        status_icon = "✅" if status == "Working" else "❌"
        print(f"   {status_icon} {service}: {status}")
    
    return f"LocalStack services test completed: {results}"

dag = DAG(
    'local_testing_dag',
    default_args=default_args,
    description='Local Testing DAG with LocalExecutor',
    schedule_interval=None,  # Manual trigger for testing
    catchup=False,
    tags=['local-testing', 'localexecutor', 'development'],
)

local_test = PythonOperator(
    task_id='test_local_setup',
    python_callable=test_local_setup,
    dag=dag,
)

localstack_services_test = PythonOperator(
    task_id='test_localstack_services',
    python_callable=test_localstack_services,
    dag=dag,
)

system_info = BashOperator(
    task_id='system_info',
    bash_command='''
        echo "🖥️ Local Development System Info:"
        echo "   Date: $(date)"
        echo "   User: $(whoami)"
        echo "   Python: $(which python)"
        echo "   Working Dir: $(pwd)"
        echo "   Executor: LocalExecutor (tasks run in webserver process)"
        echo "   Setup: Local testing environment"
        echo "   LocalStack Services: S3 + Redshift + OpenSearch"
    ''',
    dag=dag,
)

local_test >> localstack_services_test >> system_info
EOF

# =============================================================================
# STEP 8: CREATE MANAGEMENT SCRIPTS
# =============================================================================

echo "📝 Creating management scripts..."

# Activation script
cat > activate_env.sh << 'EOF'
#!/bin/bash
cd ~/podman-dev-stack
source venv/Scripts/activate

echo "✅ Virtual environment activated"
echo "📍 Project directory: $(pwd)"
echo "🐍 Python: $(which python)"

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
export AWS_ENDPOINT_URL=http://localhost:4566
export AIRFLOW_UID=50000

echo "🌍 Environment variables set for LocalStack and Airflow"
echo ""
echo "💡 Available commands:"
echo "   podman-compose up -d     # Start stack"
echo "   podman-compose down      # Stop stack"
echo "   awslocal s3 ls          # Test LocalStack"
echo "   ./restart_clean.sh      # Clean restart"
echo "   ./test_everything.sh    # Test all services"
echo "   deactivate              # Exit venv"
EOF

# Start stack script
cat > start_stack.sh << 'EOF'
#!/bin/bash
if [[ "$VIRTUAL_ENV" == "" ]]; then
    echo "❌ Virtual environment not active! Run: ./activate_env.sh"
    exit 1
fi

echo "🚀 Starting development stack..."
export AIRFLOW_UID=50000
podman-compose up -d

echo "⏳ Waiting for services to start..."
sleep 60

echo "🔍 Service status:"
podman-compose ps

echo ""
echo "🌐 Access URLs:"
echo "   Airflow:    http://localhost:8080 (admin/admin)"
echo "   Open WebUI: http://localhost:3000"
echo "   LocalStack: http://localhost:4566"
EOF

# Stop stack script
cat > stop_stack.sh << 'EOF'
#!/bin/bash
echo "🛑 Stopping development stack..."
podman-compose down
echo "✅ Stack stopped"
EOF

# Clean restart script
cat > restart_clean.sh << 'EOF'
#!/bin/bash
echo "🔄 Clean restart of all services..."
podman-compose down
sleep 5
podman-compose up -d
echo "✅ Services restarted cleanly"
EOF

# Logs script
cat > logs_all.sh << 'EOF'
#!/bin/bash
echo "📋 Showing logs for all services..."
echo "Press Ctrl+C to exit"
podman-compose logs -f
EOF

# Status check script
cat > status.sh << 'EOF'
#!/bin/bash
echo "📊 Service Status Check"
echo "======================"
echo ""
echo "🔍 Container Status:"
podman-compose ps
echo ""
echo "🌐 Service URLs:"
echo "   • Airflow:    http://localhost:8080 (admin/admin)"
echo "   • Open WebUI: http://localhost:3000"
echo "   • LocalStack: http://localhost:4566"
echo ""
echo "🏥 Health Checks:"
curl -sf http://localhost:8080/health >/dev/null && echo "   ✅ Airflow: Ready" || echo "   ❌ Airflow: Not ready"
curl -sf http://localhost:4566/_localstack/health >/dev/null && echo "   ✅ LocalStack: Ready" || echo "   ❌ LocalStack: Not ready"
curl -sf http://localhost:3000/health >/dev/null && echo "   ✅ Open WebUI: Ready" || echo "   ❌ Open WebUI: Not ready"
EOF

# Quick test script
cat > quick_test.sh << 'EOF'
#!/bin/bash
echo "⚡ Quick LocalStack Test"
echo "======================"
echo ""
echo "📦 S3 Buckets:"
awslocal s3 ls || echo "   S3 not ready"
echo ""
echo "🔴 Redshift Clusters:"
awslocal redshift describe-clusters --query 'Clusters[*].{ID:ClusterIdentifier,Status:ClusterStatus}' --output table 2>/dev/null || echo "   Redshift not ready"
echo ""
echo "🔍 OpenSearch Domains:"
awslocal opensearch list-domain-names --query 'DomainNames[*].DomainName' --output text 2>/dev/null || echo "   OpenSearch not ready"
EOF

# Clean all script
cat > clean_all.sh << 'EOF'
#!/bin/bash
echo "🧹 Complete cleanup of all resources..."
echo "⚠️  This will remove all containers, volumes, and data!"
read -p "Are you sure? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Stopping and removing all containers..."
    podman-compose down -v
    echo "Cleaning up system..."
    podman container prune -f
    podman volume prune -f
    podman image prune -f
    echo "✅ Complete cleanup finished"
else
    echo "Cleanup cancelled"
fi
EOF

# Help script
cat > help.sh << 'EOF'
#!/bin/bash
echo "🚀 PODMAN DEVELOPMENT STACK - HELP"
echo "=================================="
echo ""
echo "📂 Project Structure:"
echo "   ~/podman-dev-stack/        # Main project directory"
echo "   ├── venv/                  # Python virtual environment"
echo "   ├── airflow/dags/          # Your Airflow DAGs"
echo "   ├── localstack/init/       # LocalStack initialization"
echo "   ├── podman-compose.yml     # Service definitions"
echo "   └── *.sh                   # Management scripts"
echo ""
echo "🛠️  Management Scripts:"
echo "   ./activate_env.sh          # Activate virtual environment"
echo "   ./start_stack.sh           # Start all services"
echo "   ./stop_stack.sh            # Stop all services"
echo "   ./restart_clean.sh         # Clean restart all services"
echo "   ./test_everything.sh       # Test all services"
echo "   ./logs_all.sh              # View all service logs"
echo "   ./status.sh                # Check service status"
echo "   ./quick_test.sh            # Quick LocalStack test"
echo "   ./clean_all.sh             # Complete cleanup"
echo "   ./help.sh                  # Show this help"
echo ""
echo "🌐 Service URLs:"
echo "   • Airflow:    http://localhost:8080 (admin/admin)"
echo "   • Open WebUI: http://localhost:3000"
echo "   • LocalStack: http://localhost:4566"
echo ""
echo "🧪 Test Commands:"
echo "   awslocal s3 ls                          # List S3 buckets"
echo "   awslocal redshift describe-clusters     # List Redshift clusters"
echo "   awslocal opensearch list-domain-names   # List OpenSearch domains"
echo ""
echo "🐍 Virtual Environment:"
echo "   source venv/Scripts/activate            # Activate manually"
echo "   deactivate                              # Deactivate"
echo ""
echo "📋 Daily Workflow:"
echo "   1. ./activate_env.sh                    # Start session"
echo "   2. ./start_stack.sh                     # Start services"
echo "   3. # Develop and test...                # Your work"
echo "   4. ./stop_stack.sh                      # Stop services"
echo "   5. deactivate                           # End session"
EOF

# Test everything script
cat > test_everything.sh << 'EOF'
#!/bin/bash
echo "🧪 Testing Local Development Setup with LocalExecutor..."

echo "🔍 Service Health Checks:"
if curl -sf http://localhost:8080/health > /dev/null 2>&1; then
    echo "  ✅ Airflow (LocalExecutor): Ready"
    echo "     Note: Tasks run in webserver process, no separate scheduler needed"
else
    echo "  ⏳ Airflow (LocalExecutor): Still starting..."
fi

if curl -sf http://localhost:4566/_localstack/health > /dev/null 2>&1; then
    echo "  ✅ LocalStack: Ready"
    echo "     Services: $(curl -s http://localhost:4566/_localstack/health | grep -o '"[^"]*":\s*"[^"]*"' | head -5)"
else
    echo "  ⏳ LocalStack: Still starting..."
fi

if curl -sf http://localhost:3000/health > /dev/null 2>&1; then
    echo "  ✅ Open WebUI: Ready"
else
    echo "  ⏳ Open WebUI: Still starting..."
fi

echo ""
echo "🔍 Testing LocalStack Services (S3, Redshift, OpenSearch):"

# Test S3
echo "📦 Testing S3:"
if awslocal s3 ls > /dev/null 2>&1; then
    echo "  ✅ S3: $(awslocal s3 ls | wc -l) buckets available"
    awslocal s3 ls | sed 's/^/     /'
else
    echo "  ⏳ S3: Not ready yet"
fi

# Test Redshift
echo "🔴 Testing Redshift:"
if awslocal redshift describe-clusters > /dev/null 2>&1; then
    echo "  ✅ Redshift: $(awslocal redshift describe-clusters --query 'Clusters[*].ClusterIdentifier' --output text | wc -w) clusters"
    awslocal redshift describe-clusters --query 'Clusters[*].{ID:ClusterIdentifier,Status:ClusterStatus}' --output table 2>/dev/null | head -10
else
    echo "  ⏳ Redshift: Not ready yet"
fi

# Test OpenSearch
echo "🔍 Testing OpenSearch:"
if awslocal opensearch list-domain-names > /dev/null 2>&1; then
    echo "  ✅ OpenSearch: $(awslocal opensearch list-domain-names --query 'DomainNames[*].DomainName' --output text | wc -w) domains"
    awslocal opensearch list-domain-names --query 'DomainNames[*].DomainName' --output text | sed 's/^/     /'
    
    # Test OpenSearch cluster health via direct HTTP
    if curl -s "http://localhost:4566/test-domain/_cluster/health" > /dev/null 2>&1; then
        health_status=$(curl -s "http://localhost:4566/test-domain/_cluster/health" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        echo "     Cluster health: $health_status"
    else
        echo "     Cluster health: Initializing..."
    fi
else
    echo "  ⏳ OpenSearch: Not ready yet"
fi

echo ""
echo "📊 Container Status (LocalExecutor setup):"
podman-compose ps

echo ""
echo "🏠 Local Testing Info:"
echo "   Executor: LocalExecutor (no separate scheduler container)"
echo "   Tasks: Run directly in Airflow webserver process"
echo "   Perfect for: Local development and testing"
echo "   Services: PostgreSQL + LocalStack (S3/Redshift/OpenSearch) + Airflow + Open WebUI"

echo ""
echo "💡 If services are still starting, wait 30 more seconds and run this again"
echo "🧪 To test all services with DAG: Go to http://localhost:8080 and trigger 'local_testing_dag'"
EOF

# Logs script
cat > logs_all.sh << 'EOF'
#!/bin/bash
echo "📋 Showing logs for all services..."
echo "Press Ctrl+C to exit"
podman-compose logs -f
EOF

# Requirements file
cat > requirements.txt << 'EOF'
podman-compose==1.0.6
awscli-local>=0.20
boto3>=1.26.0
opensearch-py>=2.0.0
psycopg2-binary>=2.9.0
requests>=2.28.0
pyyaml>=6.0
EOF

chmod +x *.sh

echo "✅ Created all management scripts:"
echo "   activate_env.sh     - Activate virtual environment"
echo "   start_stack.sh      - Start all services"
echo "   stop_stack.sh       - Stop all services" 
echo "   restart_clean.sh    - Clean restart all services"
echo "   test_everything.sh  - Test all services"
echo "   logs_all.sh         - View all service logs"
echo "   status.sh           - Check service status"
echo "   quick_test.sh       - Quick LocalStack test"
echo "   clean_all.sh        - Complete cleanup" 
echo "   help.sh             - Show help and commands"

# =============================================================================
# STEP 9: CHECK PODMAN AND START SERVICES
# =============================================================================

echo ""
echo "🔍 Checking Podman setup..."

# Check if Podman is available
if ! command -v podman &> /dev/null; then
    echo "❌ Podman not found. Please install Podman Desktop first."
    exit 1
fi

echo "✅ Podman found: $(podman --version)"

# Check if Podman machine is running
if ! podman machine list --format "{{.Running}}" | grep -q "true" 2>/dev/null; then
    echo "🔧 Starting Podman machine..."
    podman machine start || echo "⚠️ Could not start Podman machine automatically"
    sleep 10
fi

# =============================================================================
# STEP 10: START THE STACK
# =============================================================================

echo ""
echo "🚀 Starting complete development stack..."

# Set environment variables
export AIRFLOW_UID=50000
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
export AWS_ENDPOINT_URL=http://localhost:4566

# Pull all images first
echo "📥 Pulling all required images..."
podman pull postgres:15
podman pull localstack/localstack:3.0
podman pull ghcr.io/open-webui/open-webui:main
podman pull "$WORKING_IMAGE"

# Start services
echo "🏃 Starting all services..."
podman-compose up -d

echo ""
echo "⏳ Services are starting... This will take 90-120 seconds for full initialization."
echo ""
echo "🔍 You can monitor progress with:"
echo "   podman-compose logs -f airflow-init    # Airflow initialization"
echo "   podman-compose logs -f localstack      # LocalStack startup"
echo "   ./logs_all.sh                          # All services"

# Wait and show initial status
sleep 45
echo ""
echo "📊 Initial service status:"
podman-compose ps

# =============================================================================
# STEP 11: FINAL INSTRUCTIONS AND TESTING
# =============================================================================

echo ""
echo "=== 🎉 LOCAL TESTING SETUP WITH LOCALEXECUTOR COMPLETE! ==="
echo ""
echo "✅ What was completed:"
echo "   • ✅ Cleaned up all existing containers and conflicts"
echo "   • ✅ Found and used working Airflow image: $WORKING_IMAGE"
echo "   • ✅ Created Python virtual environment with all packages"
echo "   • ✅ Generated configuration for LocalExecutor (no separate scheduler needed)"
echo "   • ✅ Created local testing DAGs and management scripts"
echo "   • ✅ Started all services for local development"
echo ""
echo "🏠 Local Testing Configuration:"
echo "   📁 Project Location: $(pwd)"
echo "   🐍 Virtual Environment: Active ($VIRTUAL_ENV)"
echo "   ⚡ Executor: LocalExecutor (tasks run in webserver process)"
echo "   📦 Services: PostgreSQL + LocalStack (S3 + Redshift + OpenSearch) + Airflow WebServer + Open WebUI"
echo ""
echo "⏳ WAIT 60-90 MORE SECONDS for full initialization, then access:"
echo ""
echo "🌐 Service URLs:"
echo "   🌟 Airflow:    http://localhost:8080 (admin/admin)"
echo "   🤖 Open WebUI: http://localhost:3000"
echo "   ☁️  LocalStack: http://localhost:4566"
echo "   📊 Health:     http://localhost:4566/_localstack/health"
echo ""
echo "🛠️ Management Commands:"
echo "   ./activate_env.sh       # Activate virtual environment"
echo "   ./start_stack.sh        # Start all services"
echo "   ./stop_stack.sh         # Stop all services"
echo "   ./restart_clean.sh      # Clean restart all services"
echo "   ./test_everything.sh    # Test all services"
echo "   ./logs_all.sh           # View all service logs"
echo "   ./status.sh             # Check service status"
echo "   ./quick_test.sh         # Quick LocalStack test"
echo "   ./clean_all.sh          # Complete cleanup"
echo "   ./help.sh               # Show help and all commands"
echo "   deactivate              # Exit virtual environment"
echo ""
echo "🧪 Test Commands (after 90 seconds):"
echo "   awslocal s3 ls                               # Test LocalStack S3"
echo "   awslocal redshift describe-clusters          # Test LocalStack Redshift"
echo "   awslocal opensearch list-domain-names        # Test LocalStack OpenSearch"
echo "   curl http://localhost:4566/_localstack/health # Test LocalStack Health"
echo "   curl http://localhost:8080/health             # Test Airflow"
echo ""
echo "📋 To check if everything is ready:"
echo "   ./test_everything.sh"
echo ""
echo "🔥 Your complete LOCAL TESTING environment with LocalExecutor is ready!"
echo "    📋 Available DAGs: local_testing_dag (perfect for testing LocalStack services)"
echo "    ⚡ Executor: LocalExecutor (tasks run in webserver, no scheduler needed)"
echo "    🧪 Purpose: Local development and testing"
echo "    ⏱️  Initialization: Give it 90 seconds, then run ./test_everything.sh"
echo ""
echo "📁 Created Files:"
ls -la *.sh *.yml *.txt 2>/dev/null | sed 's/^/   /'
echo ""
echo "💡 Quick Start:"
echo "   ./help.sh                    # See all available commands"
echo "   ./test_everything.sh         # Test if everything is working" 
echo "   ./status.sh                  # Check service status"

# Final test in background
echo ""
echo "🔍 Running initial health check in 60 seconds..."

# Verify all scripts were created
echo ""
echo "✅ Verifying all management scripts were created:"
SCRIPTS=("activate_env.sh" "start_stack.sh" "stop_stack.sh" "restart_clean.sh" "test_everything.sh" "logs_all.sh" "status.sh" "quick_test.sh" "clean_all.sh" "help.sh")
for script in "${SCRIPTS[@]}"; do
    if [ -f "$script" ] && [ -x "$script" ]; then
        echo "   ✅ $script - Ready"
    else
        echo "   ❌ $script - Missing or not executable"
    fi
done

sleep 60

echo ""
echo "📊 Quick Health Check:"
if curl -sf http://localhost:4566/_localstack/health > /dev/null 2>&1; then
    echo "  ✅ LocalStack: Ready"
else
    echo "  ⏳ LocalStack: Still initializing (normal, wait more)"
fi

if curl -sf http://localhost:8080/health > /dev/null 2>&1; then
    echo "  ✅ Airflow: Ready"
else
    echo "  ⏳ Airflow: Still initializing (normal, wait more)"
fi

echo ""
echo "🚀 Setup complete! Use the commands above to interact with your stack."
echo "   Run './test_everything.sh' in a few minutes to verify everything is working."