import React, { useCallback, useState } from 'react';
import ReactFlow, { MiniMap, Controls, Background } from 'react-flow-renderer';

const initialNodes = [
  { id: '1', type: 'input', data: { label: 'Trigger' }, position: { x: 50, y: 50 } },
  { id: '2', data: { label: 'HTTP Request' }, position: { x: 300, y: 50 } },
  { id: '3', type: 'output', data: { label: 'Done' }, position: { x: 600, y: 50 } }
];

const initialEdges = [
  { id: 'e1-2', source: '1', target: '2' },
  { id: 'e2-3', source: '2', target: '3' }
];

export default function Canvas() {
  const [nodes, setNodes] = useState(initialNodes);
  const [edges, setEdges] = useState(initialEdges);

  const onNodesChange = useCallback(
    (changes) => setNodes((nds) =>
      nds.map((n) => {
        const c = changes.find((x) => x.id === n.id);
        return c ? { ...n, ...c } : n;
      })
    ),
    []
  );

  const onEdgesChange = useCallback(
    (changes) =>
      setEdges((eds) =>
        eds.map((e) => {
          const c = changes.find((x) => x.id === e.id);
          return c ? { ...e, ...c } : e;
        })
      ),
    []
  );

  return (
    <ReactFlow nodes={nodes} edges={edges} onNodesChange={onNodesChange} onEdgesChange={onEdgesChange} fitView>
      <MiniMap />
      <Controls />
      <Background />
    </ReactFlow>
  );
}
