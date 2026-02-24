"""
Insights Host Inventory Mock Service
Simplified Flask API for host management
Demonstrates dual-write pattern: Own DB + Kessel Inventory API
"""

from flask import Flask, request, jsonify
import psycopg2
from psycopg2.extras import RealDictCursor
import uuid
import os
import requests
from datetime import datetime

app = Flask(__name__)

# Database configuration
DB_CONFIG = {
    'host': os.getenv('POSTGRES_HOST', 'postgres-inventory'),
    'port': int(os.getenv('POSTGRES_PORT', '5432')),
    'database': os.getenv('POSTGRES_DB', 'inventory'),
    'user': os.getenv('POSTGRES_USER', 'inventory'),
    'password': os.getenv('POSTGRES_PASSWORD', 'secretpassword')
}

# Kessel Inventory API configuration
KESSEL_INVENTORY_URL = os.getenv('KESSEL_INVENTORY_API_URL', 'http://kessel-inventory-api:8000')

def get_db_connection():
    """Get database connection"""
    return psycopg2.connect(**DB_CONFIG)

@app.route('/health', methods=['GET'])
@app.route('/healthz', methods=['GET'])
def health():
    """Health check endpoint"""
    try:
        conn = get_db_connection()
        conn.close()
        return jsonify({'status': 'healthy'}), 200
    except Exception as e:
        return jsonify({'status': 'unhealthy', 'error': str(e)}), 503

@app.route('/api/v1/hosts', methods=['GET'])
def list_hosts():
    """List all hosts"""
    try:
        workspace_id = request.args.get('workspace_id')
        
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        if workspace_id:
            cur.execute(
                'SELECT * FROM inventory.hosts WHERE workspace_id = %s ORDER BY created_at DESC',
                (workspace_id,)
            )
        else:
            cur.execute('SELECT * FROM inventory.hosts ORDER BY created_at DESC')
        
        hosts = cur.fetchall()
        cur.close()
        conn.close()
        
        return jsonify({
            'data': [dict(h) for h in hosts],
            'count': len(hosts)
        }), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/hosts', methods=['POST'])
def create_host():
    """
    Create a new host
    Dual-write pattern:
    1. Write to own PostgreSQL database (triggers CDC)
    2. Direct API call to kessel-inventory-api
    """
    try:
        data = request.get_json()
        
        host_id = str(uuid.uuid4())
        display_name = data.get('display_name')
        canonical_facts = data.get('canonical_facts', {})
        workspace_id = data.get('workspace_id')
        
        if not display_name:
            return jsonify({'error': 'display_name is required'}), 400
        
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # Step 1: Write to own database
        # This triggers CDC: Inventory DB → Debezium → Kafka → Inventory Consumer
        cur.execute(
            """
            INSERT INTO inventory.hosts (id, canonical_facts, display_name, workspace_id, created_at, updated_at)
            VALUES (%s, %s, %s, %s, %s, %s)
            RETURNING *
            """,
            (host_id, psycopg2.extras.Json(canonical_facts), display_name, workspace_id, datetime.now(), datetime.now())
        )
        
        host = dict(cur.fetchone())
        conn.commit()
        cur.close()
        conn.close()
        
        app.logger.info(f"Created host in database: {host_id} - {display_name}")
        
        # Step 2: Direct call to Kessel Inventory API
        # This is the "dual-write" - both DB and API
        try:
            kessel_response = requests.post(
                f'{KESSEL_INVENTORY_URL}/api/inventory/v1beta2/resources',
                json={
                    'resource_type': 'hbi/host',
                    'resource_id': host_id,
                    'workspace_id': workspace_id or '00000000-0000-0000-0000-000000000001',
                    'metadata': {
                        'display_name': display_name,
                        'canonical_facts': canonical_facts
                    }
                },
                timeout=5
            )
            
            if kessel_response.status_code in [200, 201]:
                app.logger.info(f"Successfully reported host to Kessel: {host_id}")
            else:
                app.logger.warning(f"Kessel API returned {kessel_response.status_code}: {kessel_response.text}")
                
        except requests.exceptions.RequestException as e:
            # Log but don't fail - CDC will eventually sync
            app.logger.warning(f"Failed to report to Kessel API (will sync via CDC): {e}")
        
        return jsonify(host), 201
        
    except Exception as e:
        app.logger.error(f"Error creating host: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/hosts/<host_id>', methods=['GET'])
def get_host(host_id):
    """Get host by ID"""
    try:
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute('SELECT * FROM inventory.hosts WHERE id = %s', (host_id,))
        host = cur.fetchone()
        cur.close()
        conn.close()
        
        if host:
            return jsonify(dict(host)), 200
        else:
            return jsonify({'error': 'Host not found'}), 404
            
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/hosts/<host_id>', methods=['PATCH'])
def update_host(host_id):
    """
    Update host
    Triggers CDC UPDATE event
    """
    try:
        data = request.get_json()
        
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # Build UPDATE query dynamically
        updates = []
        values = []
        
        if 'display_name' in data:
            updates.append('display_name = %s')
            values.append(data['display_name'])
        
        if 'canonical_facts' in data:
            updates.append('canonical_facts = %s')
            values.append(psycopg2.extras.Json(data['canonical_facts']))
        
        if not updates:
            return jsonify({'error': 'No fields to update'}), 400
        
        updates.append('updated_at = %s')
        values.append(datetime.now())
        values.append(host_id)
        
        query = f"UPDATE inventory.hosts SET {', '.join(updates)} WHERE id = %s RETURNING *"
        
        cur.execute(query, values)
        
        if cur.rowcount == 0:
            return jsonify({'error': 'Host not found'}), 404
        
        host = dict(cur.fetchone())
        conn.commit()
        cur.close()
        conn.close()
        
        app.logger.info(f"Updated host: {host_id}")
        
        return jsonify(host), 200
        
    except Exception as e:
        app.logger.error(f"Error updating host: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/hosts/<host_id>', methods=['DELETE'])
def delete_host(host_id):
    """
    Delete host
    Triggers CDC DELETE event
    """
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        cur.execute('DELETE FROM inventory.hosts WHERE id = %s', (host_id,))
        
        if cur.rowcount == 0:
            return jsonify({'error': 'Host not found'}), 404
        
        conn.commit()
        cur.close()
        conn.close()
        
        app.logger.info(f"Deleted host: {host_id}")
        
        # Try to delete from Kessel too
        try:
            requests.delete(
                f'{KESSEL_INVENTORY_URL}/api/inventory/v1/resources/hbi/host/{host_id}',
                timeout=5
            )
        except requests.exceptions.RequestException as e:
            app.logger.warning(f"Failed to delete from Kessel API: {e}")
        
        return '', 204
        
    except Exception as e:
        app.logger.error(f"Error deleting host: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/host-groups', methods=['GET'])
def list_host_groups():
    """List all host groups"""
    try:
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute('SELECT * FROM inventory.host_groups ORDER BY created_at DESC')
        groups = cur.fetchall()
        cur.close()
        conn.close()
        
        return jsonify({
            'data': [dict(g) for g in groups],
            'count': len(groups)
        }), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/host-groups', methods=['POST'])
def create_host_group():
    """Create a new host group"""
    try:
        data = request.get_json()
        
        group_id = str(uuid.uuid4())
        name = data.get('name')
        workspace_id = data.get('workspace_id')
        
        if not name:
            return jsonify({'error': 'name is required'}), 400
        
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        cur.execute(
            """
            INSERT INTO inventory.host_groups (id, name, workspace_id, created_at)
            VALUES (%s, %s, %s, %s)
            RETURNING *
            """,
            (group_id, name, workspace_id, datetime.now())
        )
        
        group = dict(cur.fetchone())
        conn.commit()
        cur.close()
        conn.close()
        
        app.logger.info(f"Created host group: {group_id} - {name}")
        
        return jsonify(group), 201
        
    except Exception as e:
        app.logger.error(f"Error creating host group: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/', methods=['GET'])
def index():
    """Root endpoint"""
    return jsonify({
        'service': 'insights-host-inventory',
        'version': '1.0.0-mock',
        'description': 'Host and Group Management',
        'endpoints': {
            'health': '/health',
            'hosts': '/api/v1/hosts',
            'host_groups': '/api/v1/host-groups'
        }
    }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8081, debug=True)
