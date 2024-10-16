public class DataSyncController {

    // Retrieve customizable objects for UI display
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getObjects() {
        List<Map<String, String>> objectList = new List<Map<String, String>>();

        try {
            List<External_ID_Mapping__mdt> activeExternalIdMappings = [
                SELECT DeveloperName, Label
                FROM External_ID_Mapping__mdt
                WHERE IsActive__c = true
            ];

            for (External_ID_Mapping__mdt mapping : activeExternalIdMappings) {
                Map<String, String> objData = new Map<String, String>{
                    'label' => mapping.DeveloperName,
                    'apiName' => mapping.DeveloperName
                };
                objectList.add(objData);
            }
        } catch (Exception e) {
            System.debug('Exception in getObjects: ' + e.getMessage());
            throw e;
        }
        return objectList;
    }
    
    // Retrieve fields for user-selected object
    @AuraEnabled(cacheable=true)
    public static List<String> getFields(String objectApiName) {
        List<String> fields = new List<String>();
        Schema.DescribeSObjectResult describeResult = Schema.getGlobalDescribe().get(objectApiName).getDescribe();
        Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
        
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            
            fields.add(fieldName);

            if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                fields.add(fieldName);
                
                List<Schema.SObjectType> referenceTo = fieldDescribe.getReferenceTo();
                for (Schema.SObjectType reference : referenceTo) {
                    fields.add(fieldDescribe.getRelationshipName() + '.');
                }
            }
        }
        return fields;
    }

    // Execute user-provided query
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> executeQuery(String query, String objectName) {
        List<Map<String, Object>> resultList = new List<Map<String, Object>>();
        try {
            // Check if the external ID field needs to be included
            External_ID_Mapping__mdt externalIdMapping = External_ID_Mapping__mdt.getInstance(objectName);
            String externalIdField = (externalIdMapping != null && externalIdMapping.IsActive__c) ? externalIdMapping.External_ID_Field__c : null;
            // If external ID field exists and is not already in the query, add it
            if (String.isNotBlank(externalIdField) && !query.toLowerCase().contains(externalIdField.toLowerCase())) {
                query = query.replaceFirst('(?i)select', 'SELECT ' + externalIdField + ',');
            }
            List<SObject> sObjectList = Database.query(query);
            for (SObject record : sObjectList) {
                Map<String, Object> recordMap = new Map<String, Object>();
                Map<String, Object> populatedFields = record.getPopulatedFieldsAsMap();
                for (String fieldName : populatedFields.keySet()) {
                    recordMap.put(fieldName, populatedFields.get(fieldName));
                }
                resultList.add(recordMap);
            }
        } catch (Exception e) {
            throw e;
        }

        return resultList;  
    }

    // Retrieve Downstream Credentials metadata
    @AuraEnabled(cacheable=true)
    public static List<Downstream_Credentials__mdt> getSandboxes() {
        return [SELECT Id, MasterLabel, Client_Id__c, Client_Secret__c, Endpoint_URL__c, Password__c, Secret_Token__c, Username__c 
                FROM Downstream_Credentials__mdt];
    }

    // Schedule weekly sync job
    @AuraEnabled
    public static void scheduleWeeklySync(String query, String objectName, String externalIdField, String toEmails, String jobName, String cronExp, Id savedQueryrecordId) {
        try {
            DownstreamSyncScheduler.scheduleJob(query, objectName, toEmails, jobName, cronExp);
        } catch (Exception e) {
            throw new AuraHandledException('An error occurred while scheduling the sync job: ' + e.getMessage());
        }
    }

    // Initiate on-demand sync
    @AuraEnabled
    public static void initiateOnDemandSync(String query, String objectName, String externalIdField, String toEmails, Id savedQueryrecordId) {
        system.debug('externalIdField----'+externalIdField);
        try {
            UpsertBatchProcessor batch = new UpsertBatchProcessor(query, objectName, toEmails, '', '', '');
            Database.executeBatch(batch);
        } catch (Exception e) {
            throw new AuraHandledException('An error occurred while initiating the sync: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String validateSync(String querys, String objectName) {
        External_ID_Mapping__mdt externalIdMapping = External_ID_Mapping__mdt.getInstance(objectName);
        if (externalIdMapping == null || !externalIdMapping.IsActive__c) {
            // If the mapping is not found or not active, we don't perform any action
            return 'External Id Mapping is not found or not active, we don`t perform any action';
        }

        if (String.isBlank(objectName)) {
            sendErrorEmail('Invalid parameters for validateSync', 
                           'Invalid parameters provided to validateSync for ' + objectName,
                           externalIdMapping.Email_Addresses__c.split(','));
            return 'Invalid parameters for validateSync';
        }

        if (String.isBlank(externalIdMapping.External_ID_Field__c)) {
            sendErrorEmail('External ID field not found', 
                           'External ID field not found for ' + objectName,
                           externalIdMapping.Email_Addresses__c.split(','));
            return 'External ID field not found';
        }

        // Query for records with null External ID values
        String whereClause = externalIdMapping.External_ID_Field__c + ' = NULL';
        String orderByClause = '';
        String groupByClause = '';
        String limitClause = '';

        // Extract ORDER BY, GROUP BY, and LIMIT clauses
        if (querys.containsIgnoreCase('ORDER BY')) {
            orderByClause = querys.substring(querys.toLowerCase().lastIndexOf('order by'));
            querys = querys.substring(0, querys.toLowerCase().lastIndexOf('order by')).trim();
        }

        if (querys.containsIgnoreCase('GROUP BY')) {
            Integer groupByIndex = querys.toLowerCase().lastIndexOf('group by');
            groupByClause = querys.substring(groupByIndex);
            querys = querys.substring(0, groupByIndex).trim();
        }

        if (querys.containsIgnoreCase('LIMIT')) {
            Integer limitIndex = querys.toLowerCase().lastIndexOf('limit');
            limitClause = querys.substring(limitIndex);
            querys = querys.substring(0, limitIndex).trim();
        }

        // Construct the new query
        String query = querys.containsIgnoreCase(' WHERE ')
            ? querys.replaceFirst('(?i)WHERE\\s+(.*?)$', 'WHERE (' + whereClause + ') AND ($1)')
            : querys + ' WHERE ' + whereClause;

        // Add back GROUP BY, ORDER BY, and LIMIT clauses
        if (!String.isEmpty(groupByClause)) {
            query += ' ' + groupByClause;
        }
        if (!String.isEmpty(orderByClause)) {
            query += ' ' + orderByClause;
        }
        if (!String.isEmpty(limitClause)) {
            query += ' ' + limitClause;
        }

        System.debug('query------' + query);
        List<SObject> invalidRecords = Database.query(query);

        if (!invalidRecords.isEmpty()) {
            String subject = 'Invalid records found for ' + objectName;
            String body = 'Records with null External ID values found for ' + objectName + ' (External ID Field: ' + externalIdMapping.External_ID_Field__c + ').\n';
            body += 'Number of invalid records: ' + invalidRecords.size() + '\n';
            body += 'Please review and update these records before proceeding with the sync.';
            
            sendErrorEmail(subject, body, externalIdMapping.Email_Addresses__c.split(','));
            return 'Records with null External ID values found for ' + objectName + ' (External ID Field: ' + externalIdMapping.External_ID_Field__c + ')';
        }

        return 'Valid';
    }

    private static void sendErrorEmail(String subject, String body, List<String> toAddresses) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(toAddresses);
        email.setSubject(subject);
        email.setPlainTextBody(body);
        Messaging.sendEmail(new Messaging.SingleEmailMessage[]{email});
    }
    
    @AuraEnabled(cacheable=true)
    public static List<String> getExternalIdFields(String objectApiName) {
        List<String> externalIdFields = new List<String>();
        
        try {
            // Get the SObject type from the API name
            SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
            
            if (objectType != null) {
                // Get all fields for the object
                Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
                
                // Iterate through all fields
                for (String fieldName : fieldMap.keySet()) {
                    Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                    
                    // Check if the field is an external ID
                    if (fieldDescribe.isExternalId() || fieldDescribe.getName().equals('Id')) {
                        externalIdFields.add(fieldName);
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error getting external ID fields: ' + e.getMessage());
        }
        
        return externalIdFields;
    }
}