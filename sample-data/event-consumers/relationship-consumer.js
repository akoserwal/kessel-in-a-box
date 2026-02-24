#!/usr/bin/env node

/**
 * Kessel CDC Event Consumer - Relationship Changes
 *
 * Consumes relationship change events from Kafka and processes them.
 * This demonstrates event-driven architecture integration with Kessel.
 */

const { Kafka } = require('kafkajs');

// Configuration
const kafka = new Kafka({
  clientId: 'kessel-relationship-consumer',
  brokers: [process.env.KAFKA_BROKER || 'localhost:29092'],
});

const consumer = kafka.consumer({
  groupId: 'relationship-processors',
  // Start from beginning to see all historical events
  fromBeginning: true,
});

const topic = 'kessel.cdc.public.relation_tuple';

// Event handlers
const handlers = {
  CREATE: (event) => {
    console.log('\n📝 Relationship CREATED:');
    console.log(`   Resource: ${event.namespace}:${event.object_id}`);
    console.log(`   Relation: ${event.relation}`);
    console.log(`   Subject:  ${event.userset_namespace}:${event.userset_object_id}#${event.userset_relation || 'self'}`);
  },

  UPDATE: (event) => {
    console.log('\n✏️  Relationship UPDATED:');
    console.log(`   Resource: ${event.namespace}:${event.object_id}`);
    console.log(`   Relation: ${event.relation}`);
  },

  DELETE: (event) => {
    console.log('\n🗑️  Relationship DELETED:');
    console.log(`   Resource: ${event.namespace}:${event.object_id}`);
    console.log(`   Relation: ${event.relation}`);
    console.log(`   Subject:  ${event.userset_namespace}:${event.userset_object_id}`);
  },
};

async function run() {
  // Connect consumer
  await consumer.connect();
  console.log('✅ Connected to Kafka');

  // Subscribe to topic
  await consumer.subscribe({ topic, fromBeginning: false });
  console.log(`📡 Subscribed to topic: ${topic}`);
  console.log('🎧 Listening for relationship changes...\n');

  // Process messages
  await consumer.run({
    eachMessage: async ({ topic, partition, message }) => {
      try {
        const value = JSON.parse(message.value.toString());

        // Debezium envelope structure
        const { before, after, op } = value;

        // Determine operation type
        let operation;
        if (op === 'c') operation = 'CREATE';
        else if (op === 'u') operation = 'UPDATE';
        else if (op === 'd') operation = 'DELETE';
        else if (op === 'r') operation = 'READ'; // Initial snapshot
        else {
          console.log('Unknown operation:', op);
          return;
        }

        // Get the event data
        const event = after || before;

        // Handle the event
        if (handlers[operation]) {
          handlers[operation](event);
        }

        // Additional metadata
        console.log(`   Operation: ${operation}`);
        console.log(`   Partition: ${partition}`);
        console.log(`   Offset:    ${message.offset}`);
        console.log(`   Timestamp: ${new Date(parseInt(message.timestamp)).toISOString()}`);

        // Example: Send to downstream system
        // await sendToDownstreamSystem(event);

        // Example: Update cache
        // await updateCache(event);

        // Example: Trigger webhook
        // await triggerWebhook(event);

      } catch (error) {
        console.error('Error processing message:', error);
      }
    },
  });
}

// Error handling
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

// Start consumer
run().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});
