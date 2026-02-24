#!/usr/bin/env node

/**
 * Insights Host Inventory Integration with Kessel
 *
 * Demonstrates how to integrate host inventory with Kessel for resource-based authorization.
 *
 * Use cases covered:
 * - Check if user can view/update a host
 * - Check fine-grained permissions (system profile, facts)
 * - List all hosts a user can access
 * - Host group management
 * - Tag-based access control
 */

const { v1 } = require("@authzed/authzed-node");

// SpiceDB client configuration
const client = v1.NewClient(
  process.env.SPICEDB_TOKEN || "testtesttesttest",
  process.env.SPICEDB_ENDPOINT || "localhost:50051",
  v1.ClientSecurity.INSECURE_PLAINTEXT_CREDENTIALS
);

// ============================================================================
// Host Permission Checking
// ============================================================================

/**
 * Check if user can perform action on a host
 */
async function canUserAccessHost(userId, hostId, permission = 'read') {
  console.log(`\n🔍 Checking: Can ${userId} ${permission} host:${hostId}?`);

  const request = v1.CheckPermissionRequest.create({
    resource: v1.ObjectReference.create({
      objectType: "host",
      objectId: hostId,
    }),
    permission: permission,
    subject: v1.SubjectReference.create({
      object: v1.ObjectReference.create({
        objectType: "user",
        objectId: userId,
      }),
    }),
  });

  try {
    const response = await client.checkPermission(request);
    const allowed = response.permissionship === v1.CheckPermissionResponse_Permissionship.HAS_PERMISSION;

    console.log(`   Result: ${allowed ? '✅ ALLOWED' : '❌ DENIED'}`);
    return allowed;
  } catch (error) {
    console.error(`   Error: ${error.message}`);
    return false;
  }
}

/**
 * Check fine-grained host permissions (system profile, facts)
 */
async function canViewHostDetails(userId, hostId, detailType = 'read_system_profile') {
  console.log(`\n🔍 Checking: Can ${userId} ${detailType} for host:${hostId}?`);

  const request = v1.CheckPermissionRequest.create({
    resource: v1.ObjectReference.create({
      objectType: "host",
      objectId: hostId,
    }),
    permission: detailType,  // read_system_profile or read_facts
    subject: v1.SubjectReference.create({
      object: v1.ObjectReference.create({
        objectType: "user",
        objectId: userId,
      }),
    }),
  });

  try {
    const response = await client.checkPermission(request);
    const allowed = response.permissionship === v1.CheckPermissionResponse_Permissionship.HAS_PERMISSION;

    console.log(`   Result: ${allowed ? '✅ ALLOWED' : '❌ DENIED'}`);
    return allowed;
  } catch (error) {
    console.error(`   Error: ${error.message}`);
    return false;
  }
}

/**
 * Check if user can delete a host
 */
async function canDeleteHost(userId, hostId) {
  return canUserAccessHost(userId, hostId, 'delete');
}

// ============================================================================
// Host Group Management
// ============================================================================

/**
 * Check host group permissions
 */
async function canManageHostGroup(userId, groupId, permission = 'manage') {
  console.log(`\n🔍 Checking: Can ${userId} ${permission} host_group:${groupId}?`);

  const request = v1.CheckPermissionRequest.create({
    resource: v1.ObjectReference.create({
      objectType: "host_group",
      objectId: groupId,
    }),
    permission: permission,
    subject: v1.SubjectReference.create({
      object: v1.ObjectReference.create({
        objectType: "user",
        objectId: userId,
      }),
    }),
  });

  try {
    const response = await client.checkPermission(request);
    const allowed = response.permissionship === v1.CheckPermissionResponse_Permissionship.HAS_PERMISSION;

    console.log(`   Result: ${allowed ? '✅ ALLOWED' : '❌ DENIED'}`);
    return allowed;
  } catch (error) {
    console.error(`   Error: ${error.message}`);
    return false;
  }
}

/**
 * Add host to a host group
 */
async function addHostToGroup(hostId, groupId) {
  console.log(`\n➕ Adding host:${hostId} to host_group:${groupId}`);

  const request = v1.WriteRelationshipsRequest.create({
    updates: [
      v1.RelationshipUpdate.create({
        operation: v1.RelationshipUpdate_Operation.TOUCH,
        relationship: v1.Relationship.create({
          resource: v1.ObjectReference.create({
            objectType: "host",
            objectId: hostId,
          }),
          relation: "host_group",
          subject: v1.SubjectReference.create({
            object: v1.ObjectReference.create({
              objectType: "host_group",
              objectId: groupId,
            }),
          }),
        }),
      }),
    ],
  });

  try {
    const response = await client.writeRelationships(request);
    console.log(`   ✅ Host added to group at token: ${response.writtenAt.token}`);
    return response.writtenAt;
  } catch (error) {
    console.error(`   ❌ Error: ${error.message}`);
    throw error;
  }
}

// ============================================================================
// Tag Management
// ============================================================================

/**
 * Check if user can apply a tag
 */
async function canApplyTag(userId, tagId) {
  console.log(`\n🔍 Checking: Can ${userId} apply tag:${tagId}?`);

  const request = v1.CheckPermissionRequest.create({
    resource: v1.ObjectReference.create({
      objectType: "tag",
      objectId: tagId,
    }),
    permission: "apply",
    subject: v1.SubjectReference.create({
      object: v1.ObjectReference.create({
        objectType: "user",
        objectId: userId,
      }),
    }),
  });

  try {
    const response = await client.checkPermission(request);
    const allowed = response.permissionship === v1.CheckPermissionResponse_Permissionship.HAS_PERMISSION;

    console.log(`   Result: ${allowed ? '✅ ALLOWED' : '❌ DENIED'}`);
    return allowed;
  } catch (error) {
    console.error(`   Error: ${error.message}`);
    return false;
  }
}

// ============================================================================
// Discovery/Lookup Functions
// ============================================================================

/**
 * List all hosts a user can read
 */
async function listUserHosts(userId, permission = 'read') {
  console.log(`\n📋 Listing hosts ${userId} can ${permission}...`);

  const request = v1.LookupResourcesRequest.create({
    resourceObjectType: "host",
    permission: permission,
    subject: v1.SubjectReference.create({
      object: v1.ObjectReference.create({
        objectType: "user",
        objectId: userId,
      }),
    }),
  });

  try {
    const hosts = [];
    for await (const response of client.lookupResources(request)) {
      hosts.push(response.resourceObjectId);
    }

    console.log(`   Found ${hosts.length} hosts:`);
    hosts.forEach(host => console.log(`     - ${host}`));
    return hosts;
  } catch (error) {
    console.error(`   Error: ${error.message}`);
    return [];
  }
}

/**
 * List all users who can access a host
 */
async function listHostUsers(hostId, permission = 'read') {
  console.log(`\n📋 Listing users who can ${permission} host:${hostId}...`);

  const request = v1.LookupSubjectsRequest.create({
    resource: v1.ObjectReference.create({
      objectType: "host",
      objectId: hostId,
    }),
    permission: permission,
    subjectObjectType: "user",
  });

  try {
    const users = [];
    for await (const response of client.lookupSubjects(request)) {
      users.push(response.subject.object.objectId);
    }

    console.log(`   Found ${users.length} users:`);
    users.forEach(user => console.log(`     - ${user}`));
    return users;
  } catch (error) {
    console.error(`   Error: ${error.message}`);
    return [];
  }
}

/**
 * List all host groups a user can view
 */
async function listUserHostGroups(userId) {
  console.log(`\n📋 Listing host groups viewable by ${userId}...`);

  const request = v1.LookupResourcesRequest.create({
    resourceObjectType: "host_group",
    permission: "view",
    subject: v1.SubjectReference.create({
      object: v1.ObjectReference.create({
        objectType: "user",
        objectId: userId,
      }),
    }),
  });

  try {
    const groups = [];
    for await (const response of client.lookupResources(request)) {
      groups.push(response.resourceObjectId);
    }

    console.log(`   Found ${groups.length} host groups:`);
    groups.forEach(group => console.log(`     - ${group}`));
    return groups;
  } catch (error) {
    console.error(`   Error: ${error.message}`);
    return [];
  }
}

// ============================================================================
// Host Lifecycle Management
// ============================================================================

/**
 * Grant user access to a host
 */
async function grantHostAccess(userId, hostId, role = 'viewer') {
  console.log(`\n✍️  Granting ${userId} ${role} access to host:${hostId}`);

  const request = v1.WriteRelationshipsRequest.create({
    updates: [
      v1.RelationshipUpdate.create({
        operation: v1.RelationshipUpdate_Operation.TOUCH,
        relationship: v1.Relationship.create({
          resource: v1.ObjectReference.create({
            objectType: "host",
            objectId: hostId,
          }),
          relation: role,  // viewer, operator, admin
          subject: v1.SubjectReference.create({
            object: v1.ObjectReference.create({
              objectType: "user",
              objectId: userId,
            }),
          }),
        }),
      }),
    ],
  });

  try {
    const response = await client.writeRelationships(request);
    console.log(`   ✅ Access granted at token: ${response.writtenAt.token}`);
    return response.writtenAt;
  } catch (error) {
    console.error(`   ❌ Error: ${error.message}`);
    throw error;
  }
}

/**
 * Transfer host ownership
 */
async function transferHostOwnership(hostId, newOwnerId) {
  console.log(`\n🔄 Transferring ownership of host:${hostId} to ${newOwnerId}`);

  // First, need to read current relationships to find old owner
  // In production, you'd query this first
  // For demo, we'll just set the new owner

  const request = v1.WriteRelationshipsRequest.create({
    updates: [
      v1.RelationshipUpdate.create({
        operation: v1.RelationshipUpdate_Operation.TOUCH,
        relationship: v1.Relationship.create({
          resource: v1.ObjectReference.create({
            objectType: "host",
            objectId: hostId,
          }),
          relation: "owner",
          subject: v1.SubjectReference.create({
            object: v1.ObjectReference.create({
              objectType: "user",
              objectId: newOwnerId,
            }),
          }),
        }),
      }),
    ],
  });

  try {
    const response = await client.writeRelationships(request);
    console.log(`   ✅ Ownership transferred at token: ${response.writtenAt.token}`);
    return response.writtenAt;
  } catch (error) {
    console.error(`   ❌ Error: ${error.message}`);
    throw error;
  }
}

// ============================================================================
// Demo Scenarios
// ============================================================================

async function runDemoScenarios() {
  console.log("╔═══════════════════════════════════════════════════════════╗");
  console.log("║   Insights Inventory → Kessel Integration Demo           ║");
  console.log("╚═══════════════════════════════════════════════════════════╝");

  // Scenario 1: Basic Host Access Checks
  console.log("\n━━━ Scenario 1: Basic Host Access Checks ━━━");
  await canUserAccessHost("alice", "web-01.acme.com", "read");    // Owner
  await canUserAccessHost("bob", "web-01.acme.com", "update");    // Via sre-team
  await canUserAccessHost("carol", "web-01.acme.com", "read");    // Via developers
  await canUserAccessHost("eve", "web-01.acme.com", "read");      // Should be DENIED

  // Scenario 2: Fine-Grained Permission Checks
  console.log("\n━━━ Scenario 2: Fine-Grained Permission Checks ━━━");
  await canViewHostDetails("carol", "web-01.acme.com", "read_system_profile");  // Via developers
  await canViewHostDetails("carol", "web-01.acme.com", "read_facts");           // Should be DENIED
  await canViewHostDetails("bob", "db-01.acme.com", "read_facts");              // Via sre-team

  // Scenario 3: Host Deletion Checks
  console.log("\n━━━ Scenario 3: Host Deletion Checks ━━━");
  await canDeleteHost("alice", "web-01.acme.com");  // Owner
  await canDeleteHost("bob", "web-01.acme.com");    // Should be DENIED (operator, not owner)
  await canDeleteHost("carol", "web-01.acme.com");  // Should be DENIED

  // Scenario 4: Host Group Management
  console.log("\n━━━ Scenario 4: Host Group Management ━━━");
  await canManageHostGroup("alice", "web-servers", "manage");  // Owner
  await canManageHostGroup("bob", "web-servers", "add_host");  // Via sre-team admin
  await canManageHostGroup("carol", "web-servers", "view");    // Via developers member

  // Scenario 5: Tag Application
  console.log("\n━━━ Scenario 5: Tag Application ━━━");
  await canApplyTag("bob", "production");   // Via sre-team
  await canApplyTag("carol", "staging");    // Via developers
  await canApplyTag("carol", "production"); // Should be DENIED

  // Scenario 6: List User Resources
  console.log("\n━━━ Scenario 6: List User Resources ━━━");
  await listUserHosts("bob", "read");
  await listUserHosts("carol", "update");
  await listUserHostGroups("carol");

  // Scenario 7: Host Access Management
  console.log("\n━━━ Scenario 7: Host Access Management ━━━");

  // Grant eve viewer access to a host
  await grantHostAccess("eve", "web-02.acme.com", "viewer");

  // Verify access was granted
  await canUserAccessHost("eve", "web-02.acme.com", "read");  // Should be ALLOWED

  // Scenario 8: Ownership Transfer
  console.log("\n━━━ Scenario 8: Ownership Transfer ━━━");

  // Transfer ownership of a host
  await transferHostOwnership("web-02.acme.com", "bob");

  // Verify new owner can delete
  await canDeleteHost("bob", "web-02.acme.com");  // Should be ALLOWED

  // Scenario 9: Host Users Lookup
  console.log("\n━━━ Scenario 9: Host Users Lookup ━━━");
  await listHostUsers("web-01.acme.com", "read");
  await listHostUsers("web-01.acme.com", "update");

  // Scenario 10: Workspace-level Access
  console.log("\n━━━ Scenario 10: Workspace-level Access Inheritance ━━━");

  // Users with workspace access automatically get host access via inheritance
  await canUserAccessHost("carol", "db-01.acme.com", "read");  // Via workspace:production view

  console.log("\n╔═══════════════════════════════════════════════════════════╗");
  console.log("║   Demo Completed Successfully!                            ║");
  console.log("╚═══════════════════════════════════════════════════════════╝\n");
}

// Run the demo
if (require.main === module) {
  runDemoScenarios()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("Demo failed:", error);
      process.exit(1);
    });
}

module.exports = {
  canUserAccessHost,
  canViewHostDetails,
  canDeleteHost,
  canManageHostGroup,
  canApplyTag,
  listUserHosts,
  listHostUsers,
  listUserHostGroups,
  grantHostAccess,
  transferHostOwnership,
  addHostToGroup,
};
