#!/usr/bin/env node

/**
 * Kessel CDC Event Consumer - Schema Changes
 *
 * Consumes schema change events from Kafka and processes them.
 * This demonstrates how to react to authorization schema updates.
 */

const { Kafka } = require('kafkajs');

// Configuration
const kafka = new Kafka({
  clientId: 'kessel-schema-consumer',
  brokers: [process.env.KAFKA_BROKER || 'localhost:29092'],
});

const consumer = kafka.consumer({
  groupId: 'schema-processors',
  fromBeginning: true,
});

const topic = 'kessel.cdc.public.namespace_config';

async function run() {
  await consumer.connect();
  console.log('✅ Connected to Kafka');

  await consumer.subscribe({ topic, fromBeginning: false });
  console.log(`📡 Subscribed to topic: ${topic}`);
  console.log('🎧 Listening for schema changes...\n');

  await consumer.run({
    eachMessage: async ({ topic, partition, message }) => {
      try {
        const value = JSON.parse(message.value.toString());
        const { before, after, op } = value;

        let operation;
        if (op === 'c') operation = 'CREATE';
        else if (op === 'u') operation = 'UPDATE';
        else if (op === 'd') operation = 'DELETE';
        else if (op === 'r') operation = 'READ';
        else return;

        const event = after || before;

        console.log(`\n📋 Schema ${operation}:`);
        console.log(`   Namespace: ${event.namespace}`);

        if (event.serialized_config) {
          // Try to parse the schema definition
          try {
            const config = JSON.parse(event.serialized_config);
            if (config.definition) {
              console.log(`   Definition preview:`);
              console.log(`   ${config.definition.substring(0, 100)}...`);
            }
          } catch (e) {
            console.log(`   Config size: ${event.serialized_config.length} bytes`);
          }
        }

        console.log(`   Created XID: ${event.created_xid}`);
        console.log(`   Partition: ${partition}`);
        console.log(`   Offset: ${message.offset}`);

        // Example: Invalidate schema cache
        // await invalidateSchemaCache(event.namespace);

        // Example: Notify applications of schema change
        // await notifyApplications(event.namespace);

        // Example: Validate schema compatibility
        // await validateSchemaCompatibility(event);

      } catch (error) {
        console.error('Error processing message:', error);
      }
    },
  });
}

process.on('SIGTERM', async () => {
  console.log('\nShutting down...');
  await consumer.disconnect();
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('\nShutting down...');
  await consumer.disconnect();
  process.exit(0);
});

run().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});
