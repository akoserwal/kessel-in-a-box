"""
Insights RBAC Mock Service
Simplified Django-like API for workspace and role management
Demonstrates CDC integration with Kessel
"""

from flask import Flask, request, jsonify
import psycopg2
from psycopg2.extras import RealDictCursor
import uuid
import os
from datetime import datetime

app = Flask(__name__)

# Database configuration
DB_CONFIG = {
    'host': os.getenv('POSTGRES_HOST', 'postgres-rbac'),
    'port': int(os.getenv('POSTGRES_PORT', '5432')),
    'database': os.getenv('POSTGRES_DB', 'rbac'),
    'user': os.getenv('POSTGRES_USER', 'rbac'),
    'password': os.getenv('POSTGRES_PASSWORD', 'secretpassword')
}

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

@app.route('/api/v1/workspaces', methods=['GET'])
def list_workspaces():
    """List all workspaces"""
    try:
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute('SELECT * FROM rbac.workspaces ORDER BY created_at DESC')
        workspaces = cur.fetchall()
        cur.close()
        conn.close()
        
        return jsonify({
            'data': [dict(w) for w in workspaces],
            'count': len(workspaces)
        }), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/workspaces', methods=['POST'])
def create_workspace():
    """
    Create a new workspace
    This triggers CDC: RBAC DB → Debezium → Kafka → Relations Sink → Relations API
    """
    try:
        data = request.get_json()
        
        workspace_id = str(uuid.uuid4())
        name = data.get('name')
        description = data.get('description', '')
        
        if not name:
            return jsonify({'error': 'name is required'}), 400
        
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # Insert into RBAC database
        # This INSERT triggers PostgreSQL WAL → Debezium → Kafka
        cur.execute(
            """
            INSERT INTO rbac.workspaces (id, name, description, created_at, updated_at)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING *
            """,
            (workspace_id, name, description, datetime.now(), datetime.now())
        )
        
        workspace = dict(cur.fetchone())
        conn.commit()
        cur.close()
        conn.close()
        
        app.logger.info(f"Created workspace: {workspace_id} - {name}")
        app.logger.info("CDC will propagate this to Kessel via Kafka")
        
        return jsonify(workspace), 201
        
    except Exception as e:
        app.logger.error(f"Error creating workspace: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/workspaces/<workspace_id>', methods=['GET'])
def get_workspace(workspace_id):
    """Get workspace by ID"""
    try:
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute('SELECT * FROM rbac.workspaces WHERE id = %s', (workspace_id,))
        workspace = cur.fetchone()
        cur.close()
        conn.close()
        
        if workspace:
            return jsonify(dict(workspace)), 200
        else:
            return jsonify({'error': 'Workspace not found'}), 404
            
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/workspaces/<workspace_id>', methods=['DELETE'])
def delete_workspace(workspace_id):
    """
    Delete workspace
    This triggers CDC DELETE event → Kafka → Relations Sink → deletes tuples
    """
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Delete from RBAC database
        # This DELETE triggers PostgreSQL WAL → Debezium → Kafka
        cur.execute('DELETE FROM rbac.workspaces WHERE id = %s', (workspace_id,))
        
        if cur.rowcount == 0:
            return jsonify({'error': 'Workspace not found'}), 404
        
        conn.commit()
        cur.close()
        conn.close()
        
        app.logger.info(f"Deleted workspace: {workspace_id}")
        app.logger.info("CDC will propagate DELETE to Kessel via Kafka")
        
        return '', 204
        
    except Exception as e:
        app.logger.error(f"Error deleting workspace: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/roles', methods=['GET'])
def list_roles():
    """List all roles"""
    try:
        workspace_id = request.args.get('workspace_id')
        
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        if workspace_id:
            cur.execute(
                'SELECT * FROM rbac.roles WHERE workspace_id = %s ORDER BY created_at DESC',
                (workspace_id,)
            )
        else:
            cur.execute('SELECT * FROM rbac.roles ORDER BY created_at DESC')
        
        roles = cur.fetchall()
        cur.close()
        conn.close()
        
        return jsonify({
            'data': [dict(r) for r in roles],
            'count': len(roles)
        }), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/roles', methods=['POST'])
def create_role():
    """
    Create a new role
    Triggers CDC to create role tuples in SpiceDB
    """
    try:
        data = request.get_json()
        
        role_id = str(uuid.uuid4())
        name = data.get('name')
        workspace_id = data.get('workspace_id')
        
        if not name or not workspace_id:
            return jsonify({'error': 'name and workspace_id are required'}), 400
        
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # Insert into RBAC database
        cur.execute(
            """
            INSERT INTO rbac.roles (id, name, workspace_id, created_at, updated_at)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING *
            """,
            (role_id, name, workspace_id, datetime.now(), datetime.now())
        )
        
        role = dict(cur.fetchone())
        conn.commit()
        cur.close()
        conn.close()
        
        app.logger.info(f"Created role: {role_id} - {name} in workspace {workspace_id}")
        
        return jsonify(role), 201
        
    except Exception as e:
        app.logger.error(f"Error creating role: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/', methods=['GET'])
def index():
    """Root endpoint"""
    return jsonify({
        'service': 'insights-rbac',
        'version': '1.0.0-mock',
        'description': 'Workspace and Role Management',
        'endpoints': {
            'health': '/health',
            'workspaces': '/api/v1/workspaces',
            'roles': '/api/v1/roles'
        }
    }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)
