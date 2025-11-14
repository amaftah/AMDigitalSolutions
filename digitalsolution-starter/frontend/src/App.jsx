import React, { useEffect, useState } from 'react';
import Canvas from './components/Canvas';
import axios from 'axios';

export default function App() {
  const [flows, setFlows] = useState([]);

  useEffect(() => {
    async function load() {
      try {
        const res = await axios.get(`${process.env.API_BASE_URL || 'http://localhost:4000/api'}/flows`);
        setFlows(res.data);
      } catch (e) {
        console.warn('could not load flows', e.message);
      }
    }
    load();
  }, []);

  return (
    <div style={{display:'flex',height:'100vh'}}>
      <div style={{width:300,padding:12,borderRight:'1px solid #eee'}}>
        <h3>Flows</h3>
        <ul>
          {flows.map(f => <li key={f.id}>{f.name || f.id}</li>)}
        </ul>
      </div>
      <div style={{flex:1}}>
        <Canvas />
      </div>
    </div>
  );
}
