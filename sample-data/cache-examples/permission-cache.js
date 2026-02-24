#!/usr/bin/env node

/**
 * Permission Check with Redis Caching
 *
 * Demonstrates cache-aside pattern for permission checks.
 * Caches permission check results to reduce load on SpiceDB.
 */

const { v1 } = require('@authzed/authzed-node');
const Redis = require('ioredis');
const grpc = require('@grpc/grpc-js');

// Configuration
const SPICEDB_ENDPOINT = process.env.SPICEDB_ENDPOINT || 'localhost:50051';
const SPICEDB_TOKEN = process.env.SPICEDB_TOKEN || 'testtesttesttest';
const REDIS_HOST = process.env.REDIS_HOST || 'localhost';
const REDIS_PORT = process.env.REDIS_PORT || 6379;
const REDIS_PASSWORD = process.env.REDIS_PASSWORD || 'redispassword';

// Cache TTL (seconds)
const CACHE_TTL = parseInt(process.env.CACHE_TTL || '60');

// Initialize clients
const redis = new Redis({
  host: REDIS_HOST,
  port: REDIS_PORT,
  password: REDIS_PASSWORD,
});

const spicedb = v1.NewClient(
  SPICEDB_TOKEN,
  SPICEDB_ENDPOINT,
  v1.ClientSecurity.INSECURE_PLAINTEXT_CREDENTIALS
);

/**
 * Generate cache key for permission check
 */
function getCacheKey(resource, permission, subject) {
  return `kessel:perm:${resource.objectType}:${resource.objectId}:${permission}:${subject.object.objectType}:${subject.object.objectId}`;
}

/**
 * Check permission with caching
 *
 * @param {Object} resource - Resource to check
 * @param {string} permission - Permission name
 * @param {Object} subject - Subject to check
 * @returns {Promise<Object>} Permission check result with cache metadata
 */
async function checkPermissionCached(resource, permission, subject) {
  const startTime = Date.now();
  const cacheKey = getCacheKey(resource, permission, subject);

  // Try cache first
  const cached = await redis.get(cacheKey);

  if (cached) {
    const result = JSON.parse(cached);
    const latency = Date.now() - startTime;

    console.log(`✅ CACHE HIT (${latency}ms)`);
    console.log(`   Key: ${cacheKey}`);
    console.log(`   Result: ${result.permissionship}`);
    console.log(`   Cached at: ${new Date(result.cached_at * 1000).toISOString()}`);

    return {
      ...result,
      cached: true,
      latency,
    };
  }

  // Cache miss - check SpiceDB
  console.log(`❌ CACHE MISS - Querying SpiceDB...`);

  try {
    const response = await spicedb.checkPermission({
      resource,
      permission,
      subject,
      consistency: {
        fullyConsistent: true,
      },
    });

    const result = {
      permissionship: v1.CheckPermissionResponse_Permissionship[response.permissionship],
      checked_at: response.checkedAt?.token || null,
      cached_at: Math.floor(Date.now() / 1000),
    };

    // Store in cache
    await redis.setex(cacheKey, CACHE_TTL, JSON.stringify(result));

    const latency = Date.now() - startTime;

    console.log(`✅ PERMISSION CHECK COMPLETE (${latency}ms)`);
    console.log(`   Result: ${result.permissionship}`);
    console.log(`   Cached for: ${CACHE_TTL}s`);

    return {
      ...result,
      cached: false,
      latency,
    };

  } catch (error) {
    console.error('❌ Permission check failed:', error.message);
    throw error;
  }
}

/**
 * Invalidate cache for a resource
 */
async function invalidateResourceCache(resourceType, resourceId) {
  const pattern = `kessel:perm:${resourceType}:${resourceId}:*`;
  const keys = await redis.keys(pattern);

  if (keys.length > 0) {
    await redis.del(...keys);
    console.log(`🗑️  Invalidated ${keys.length} cache keys for ${resourceType}:${resourceId}`);
  } else {
    console.log(`ℹ️  No cache keys found for ${resourceType}:${resourceId}`);
  }
}

/**
 * Get cache statistics
 */
async function getCacheStats() {
  const info = await redis.info('stats');

  const hits = parseInt(info.match(/keyspace_hits:(\d+)/)?.[1] || 0);
  const misses = parseInt(info.match(/keyspace_misses:(\d+)/)?.[1] || 0);
  const evicted = parseInt(info.match(/evicted_keys:(\d+)/)?.[1] || 0);
  const expired = parseInt(info.match(/expired_keys:(\d+)/)?.[1] || 0);

  const total = hits + misses;
  const hitRate = total > 0 ? ((hits / total) * 100).toFixed(2) : 0;

  return {
    hits,
    misses,
    evicted,
    expired,
    total,
    hitRate: parseFloat(hitRate),
  };
}

// Example usage
async function example() {
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('  Permission Check with Redis Caching');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log();

  const resource = {
    objectType: 'repository',
    objectId: 'acmecorp/backend',
  };

  const subject = {
    object: {
      objectType: 'user',
      objectId: 'bob',
    },
  };

  const permission = 'read';

  try {
    // First check - will be cache miss
    console.log('Check 1: First permission check (cache miss expected)\n');
    await checkPermissionCached(resource, permission, subject);
    console.log();

    // Second check - should be cache hit
    console.log('Check 2: Same permission check (cache hit expected)\n');
    await checkPermissionCached(resource, permission, subject);
    console.log();

    // Third check after short delay - still cache hit
    console.log('Waiting 2 seconds...\n');
    await new Promise(resolve => setTimeout(resolve, 2000));

    console.log('Check 3: After delay (cache hit expected)\n');
    await checkPermissionCached(resource, permission, subject);
    console.log();

    // Display cache statistics
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('  Cache Statistics');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    const stats = await getCacheStats();
    console.log(`  Hits:      ${stats.hits}`);
    console.log(`  Misses:    ${stats.misses}`);
    console.log(`  Hit Rate:  ${stats.hitRate}%`);
    console.log(`  Evicted:   ${stats.evicted}`);
    console.log(`  Expired:   ${stats.expired}`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  } catch (error) {
    console.error('Example failed:', error);
  } finally {
    await redis.quit();
    process.exit(0);
  }
}

// Export for use as library
module.exports = {
  checkPermissionCached,
  invalidateResourceCache,
  getCacheStats,
};

// Run example if executed directly
if (require.main === module) {
  example().catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
}
