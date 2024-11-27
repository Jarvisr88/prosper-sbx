'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';

interface TestResult {
  success: boolean;
  data?: Record<string, unknown>;
  error?: string;
}

interface TestResults {
  performanceScores?: TestResult;
  projectAssignments?: TestResult;
  metricsHistory?: TestResult;
  systemStatus?: TestResult;
}

type TestName = keyof TestResults;

export default function DatabaseTestPage() {
  const [results, setResults] = useState<TestResults>({});
  const [loading, setLoading] = useState<TestName | null>(null);

  const runTest = async (testName: TestName, endpoint: string) => {
    setLoading(testName);
    try {
      const response = await fetch(`/api/admin/test/${endpoint}`);
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      const data = await response.json();
      setResults((prev) => ({
        ...prev,
        [testName]: { success: true, data },
      }));
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An unknown error occurred';
      setResults((prev) => ({
        ...prev,
        [testName]: { success: false, error: errorMessage },
      }));
    }
    setLoading(null);
  };

  const renderTestCard = (
    title: string,
    testName: TestName,
    endpoint: string
  ) => (
    <Card className="p-6">
      <h2 className="text-xl font-semibold mb-4">{title}</h2>
      <Button
        onClick={() => runTest(testName, endpoint)}
        disabled={loading === testName}
      >
        {loading === testName ? 'Testing...' : `Test ${title}`}
      </Button>
      {results[testName] && (
        <pre className="mt-4 p-4 bg-gray-100 rounded overflow-auto max-h-60">
          {JSON.stringify(results[testName], null, 2)}
        </pre>
      )}
    </Card>
  );

  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold mb-6">Database Connectivity Tests</h1>
      
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {renderTestCard('Performance Scores', 'performanceScores', 'performance')}
        {renderTestCard('Project Assignments', 'projectAssignments', 'projects')}
        {renderTestCard('Metrics History', 'metricsHistory', 'metrics')}
        {renderTestCard('System Status', 'systemStatus', 'status')}
      </div>
    </div>
  );
} 