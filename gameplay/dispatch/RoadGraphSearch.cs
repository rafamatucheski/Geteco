using System;
using System.Collections.Generic;
using Godot;

/// Espelho nativo do grafo de ruas de NativeTrafficRoutes para o DispatchRoadRouter.gd.
/// O GDScript continua dono do grafo e do Curve3D; aqui ficam só as duas buscas que custavam
/// pico de quadro: a aresta mais próxima (varria o grafo inteiro) e o Dijkstra.
/// A ordem das arestas, o heap e os desempates replicam o GDScript, para o resultado ser o mesmo.
public partial class RoadGraphSearch : RefCounted
{
	private const float CellSize = 48.0f;
	private const int MaxRings = 64;

	private Vector3[] _vertices = Array.Empty<Vector3>();
	private int _edgeCount;
	private int[] _edgeFrom = Array.Empty<int>();
	private int[] _edgeTo = Array.Empty<int>();
	private Vector3[] _edgeDirection = Array.Empty<Vector3>();
	private Vector3[] _edgeA = Array.Empty<Vector3>();
	private Vector3[] _edgeB = Array.Empty<Vector3>();
	private float[] _edgeLength = Array.Empty<float>();

	// Adjacência em CSR, na mesma ordem em que edges[node] aparece no GDScript.
	private int[] _adjStart = Array.Empty<int>();
	private int[] _adjEdge = Array.Empty<int>();

	private readonly Dictionary<long, int[]> _grid = new();
	private int[] _stamp = Array.Empty<int>();
	private int _stampGeneration;

	private readonly Dictionary<long, double> _blocked = new();
	private double _clock;

	private double[] _distance = Array.Empty<double>();
	private int[] _previous = Array.Empty<int>();
	private readonly MinHeap _heap = new();

	public void Build(Vector3[] vertices, int[] edgeFrom, int[] edgeTo, double[] width, int[] lanes, int[] oneWay)
	{
		_vertices = vertices;
		_edgeCount = 0;
		var count = edgeFrom.Length;
		_edgeFrom = new int[count];
		_edgeTo = new int[count];
		_edgeDirection = new Vector3[count];
		_edgeA = new Vector3[count];
		_edgeB = new Vector3[count];
		_edgeLength = new float[count];
		var valid = new List<int>(count);
		for (var i = 0; i < count; i++)
		{
			if (edgeFrom[i] < 0 || edgeFrom[i] >= vertices.Length || edgeTo[i] < 0 || edgeTo[i] >= vertices.Length) continue;
			valid.Add(i);
		}
		_edgeCount = valid.Count;
		for (var slot = 0; slot < _edgeCount; slot++)
		{
			var i = valid[slot];
			_edgeFrom[slot] = edgeFrom[i];
			_edgeTo[slot] = edgeTo[i];
			var a = vertices[edgeFrom[i]];
			var b = vertices[edgeTo[i]];
			var direction = (b - a).Normalized();
			// Mesmo cálculo de NativeTrafficRoutes._lane_offset (faixa 0).
			var laneCount = Math.Max(1, lanes[i]);
			var offset = width[i] / (2.0 * laneCount) * 0.5;
			if (oneWay[i] != 0) offset = width[i] / laneCount * 0.5 - width[i] * 0.5;
			var shift = direction.Cross(Vector3.Up) * (float)offset;
			_edgeDirection[slot] = direction;
			_edgeA[slot] = a + shift;
			_edgeB[slot] = b + shift;
			_edgeLength[slot] = vertices[edgeTo[i]].DistanceTo(vertices[edgeFrom[i]]);
		}

		_adjStart = new int[vertices.Length + 1];
		for (var slot = 0; slot < _edgeCount; slot++) _adjStart[_edgeFrom[slot] + 1]++;
		for (var v = 0; v < vertices.Length; v++) _adjStart[v + 1] += _adjStart[v];
		_adjEdge = new int[_edgeCount];
		var fill = new int[vertices.Length];
		for (var slot = 0; slot < _edgeCount; slot++)
		{
			var from = _edgeFrom[slot];
			_adjEdge[_adjStart[from] + fill[from]++] = slot;
		}

		BuildGrid();
		_stamp = new int[_edgeCount];
		_stampGeneration = 0;
		_distance = new double[vertices.Length];
		_previous = new int[vertices.Length];
		_blocked.Clear();
	}

	public void SetClock(double clock) => _clock = clock;

	public void BlockEdge(int from, int to, double expiry) => _blocked[Key(from, to)] = expiry;

	public void ClearBlocks() => _blocked.Clear();

	private static long Key(int from, int to) => ((long)from << 32) | (uint)to;

	private bool IsBlocked(int from, int to)
	{
		if (_blocked.Count == 0) return false;
		var key = Key(from, to);
		if (!_blocked.TryGetValue(key, out var expiry)) return false;
		if (_clock >= expiry)
		{
			_blocked.Remove(key);
			return false;
		}
		return true;
	}

	private static long CellKey(int x, int z) => ((long)x << 32) | (uint)z;

	private static int CellOf(float value) => (int)Math.Floor(value / CellSize);

	private void BuildGrid()
	{
		_grid.Clear();
		var lists = new Dictionary<long, List<int>>();
		for (var slot = 0; slot < _edgeCount; slot++)
		{
			var a = _edgeA[slot];
			var b = _edgeB[slot];
			var x0 = CellOf(Math.Min(a.X, b.X));
			var x1 = CellOf(Math.Max(a.X, b.X));
			var z0 = CellOf(Math.Min(a.Z, b.Z));
			var z1 = CellOf(Math.Max(a.Z, b.Z));
			for (var x = x0; x <= x1; x++)
			{
				for (var z = z0; z <= z1; z++)
				{
					var key = CellKey(x, z);
					if (!lists.TryGetValue(key, out var list))
					{
						list = new List<int>();
						lists[key] = list;
					}
					list.Add(slot);
				}
			}
		}
		foreach (var pair in lists) _grid[pair.Key] = pair.Value.ToArray();
	}

	private float _bestDistance;
	private int _bestEdge;
	private Vector3 _bestClosest;

	private void Consider(int slot, Vector3 point, bool skipBlocked, bool useHeading, Vector3 headingNormal)
	{
		if (skipBlocked && IsBlocked(_edgeFrom[slot], _edgeTo[slot])) return;
		if (useHeading && _edgeDirection[slot].Dot(headingNormal) < 0.0f) return;
		var closest = Geometry3D.GetClosestPointToSegment(point, _edgeA[slot], _edgeB[slot]);
		var distance = closest.DistanceSquaredTo(point);
		// Menor distância; empate fica com a aresta de menor índice, como o primeiro-vence do GDScript.
		if (distance < _bestDistance || (distance == _bestDistance && _bestEdge >= 0 && slot < _bestEdge))
		{
			_bestDistance = distance;
			_bestEdge = slot;
			_bestClosest = closest;
		}
	}

	/// Devolve {"index": posição na lista plana de arestas, "closest": Vector3, "distance": float}
	/// ou um dicionário vazio quando nenhuma aresta serve.
	public Godot.Collections.Dictionary NearestEdge(Vector3 point, bool skipBlocked, Vector3 heading)
	{
		var result = new Godot.Collections.Dictionary();
		if (_edgeCount == 0) return result;
		var useHeading = (double)heading.LengthSquared() > 0.01;
		var headingNormal = useHeading ? heading.Normalized() : Vector3.Zero;
		_bestDistance = float.PositiveInfinity;
		_bestEdge = -1;
		_bestClosest = Vector3.Zero;

		var settled = false;
		var cx = CellOf(point.X);
		var cz = CellOf(point.Z);
		_stampGeneration++;
		for (var ring = 0; ring <= MaxRings; ring++)
		{
			if (ring == 0) VisitCell(cx, cz, point, skipBlocked, useHeading, headingNormal);
			else
			{
				for (var dx = -ring; dx <= ring; dx++)
				{
					VisitCell(cx + dx, cz - ring, point, skipBlocked, useHeading, headingNormal);
					VisitCell(cx + dx, cz + ring, point, skipBlocked, useHeading, headingNormal);
				}
				for (var dz = -ring + 1; dz <= ring - 1; dz++)
				{
					VisitCell(cx - ring, cz + dz, point, skipBlocked, useHeading, headingNormal);
					VisitCell(cx + ring, cz + dz, point, skipBlocked, useHeading, headingNormal);
				}
			}
			// Uma aresta ainda não vista está a pelo menos ring*CellSize em planta.
			if (_bestEdge >= 0 && Math.Sqrt(_bestDistance) < ring * CellSize)
			{
				settled = true;
				break;
			}
		}
		if (!settled)
		{
			// Ponto longe do grafo: varredura completa, igual ao GDScript.
			_bestDistance = float.PositiveInfinity;
			_bestEdge = -1;
			for (var slot = 0; slot < _edgeCount; slot++) Consider(slot, point, skipBlocked, useHeading, headingNormal);
		}
		if (_bestEdge < 0) return result;
		result["index"] = _bestEdge;
		result["closest"] = _bestClosest;
		result["distance"] = Math.Sqrt(_bestDistance);
		return result;
	}

	private void VisitCell(int x, int z, Vector3 point, bool skipBlocked, bool useHeading, Vector3 headingNormal)
	{
		if (!_grid.TryGetValue(CellKey(x, z), out var cell)) return;
		foreach (var slot in cell)
		{
			if (_stamp[slot] == _stampGeneration) continue;
			_stamp[slot] = _stampGeneration;
			Consider(slot, point, skipBlocked, useHeading, headingNormal);
		}
	}

	/// Mesma varredura completa do GDScript; serve de referência nos testes.
	public Godot.Collections.Dictionary NearestEdgeBrute(Vector3 point, bool skipBlocked, Vector3 heading)
	{
		var result = new Godot.Collections.Dictionary();
		var useHeading = (double)heading.LengthSquared() > 0.01;
		var headingNormal = useHeading ? heading.Normalized() : Vector3.Zero;
		_bestDistance = float.PositiveInfinity;
		_bestEdge = -1;
		for (var slot = 0; slot < _edgeCount; slot++) Consider(slot, point, skipBlocked, useHeading, headingNormal);
		if (_bestEdge < 0) return result;
		result["index"] = _bestEdge;
		result["closest"] = _bestClosest;
		result["distance"] = Math.Sqrt(_bestDistance);
		return result;
	}

	private void Dijkstra(int source, double costLimit, int target)
	{
		Array.Fill(_distance, double.PositiveInfinity);
		Array.Fill(_previous, -1);
		_heap.Clear();
		_distance[source] = 0.0;
		_heap.Push(0.0, source);
		while (!_heap.IsEmpty)
		{
			var node = _heap.Pop();
			var settled = _heap.PoppedCost;
			if (settled > _distance[node] || settled > costLimit) continue;
			if (node == target) break;
			for (var i = _adjStart[node]; i < _adjStart[node + 1]; i++)
			{
				var slot = _adjEdge[i];
				var to = _edgeTo[slot];
				if (IsBlocked(node, to)) continue;
				var cost = settled + _edgeLength[slot];
				if (cost < _distance[to])
				{
					_distance[to] = cost;
					_previous[to] = node;
					_heap.Push(cost, to);
				}
			}
		}
	}

	/// Caminho mais curto de `source` a `target`, parando ao assentar o destino.
	/// {"found": bool, "chain": int[] de source a target, "distance": double}
	public Godot.Collections.Dictionary Plan(int source, int target)
	{
		var result = new Godot.Collections.Dictionary { ["found"] = false };
		if (source < 0 || target < 0 || source >= _vertices.Length || target >= _vertices.Length) return result;
		Dijkstra(source, double.PositiveInfinity, target);
		if (double.IsPositiveInfinity(_distance[target])) return result;
		var reverse = new List<int> { target };
		var guard = 0;
		while (reverse[^1] != source && guard < 100000)
		{
			var back = _previous[reverse[^1]];
			if (back < 0) return result;
			reverse.Add(back);
			guard++;
		}
		reverse.Reverse();
		result["found"] = true;
		result["chain"] = reverse.ToArray();
		result["distance"] = _distance[target];
		return result;
	}

	/// Dijkstra completo até `costLimit` (rota de saída): {"distance": double[], "previous": int[]}.
	public Godot.Collections.Dictionary Search(int source, double costLimit)
	{
		var result = new Godot.Collections.Dictionary();
		if (source < 0 || source >= _vertices.Length) return result;
		Dijkstra(source, costLimit, -1);
		result["distance"] = (double[])_distance.Clone();
		result["previous"] = (int[])_previous.Clone();
		return result;
	}

	/// Reamostra a curva de rota como o `_build` do GDScript: acha o ponto da curva mais perto do fim
	/// e a refaz de `begin` até lá, a cada `step` metros. As amostras são as mesmas chamadas ao
	/// Curve3D (sample_baked cúbico); só o laço sai do interpretador e o último ponto fica em variável.
	public Curve3D BuildPath(Curve3D source, double begin, double window, Vector3 endPoint, double step, double bakeInterval)
	{
		var length = source.GetBakedLength();
		var finish = (double)length;
		var finishDistance = double.PositiveInfinity;
		var offset = window;
		while (offset <= length)
		{
			var separation = source.SampleBaked((float)offset, true).DistanceSquaredTo(endPoint);
			if (separation < finishDistance)
			{
				finishDistance = separation;
				finish = offset;
			}
			offset += 0.5;
		}
		finish = Math.Min(length, Math.Max(finish, begin + 1.0));
		var curve = new Curve3D { BakeInterval = (float)bakeInterval };
		var count = 0;
		var last = Vector3.Zero;
		var cursor = begin;
		while (cursor < finish)
		{
			var sampled = source.SampleBaked((float)cursor, true);
			if (count == 0 || (double)last.DistanceSquaredTo(sampled) >= 0.0001)
			{
				curve.AddPoint(sampled);
				last = sampled;
				count++;
			}
			cursor += step;
		}
		var finalPoint = source.SampleBaked((float)finish, true);
		if (count == 0 || (double)last.DistanceSquaredTo(finalPoint) >= 0.0001) curve.AddPoint(finalPoint);
		return curve;
	}

	// Mesmo heap de DispatchRoadRouter.MinHeap: subida com <=, descida com <.
	private sealed class MinHeap
	{
		private double[] _costs = new double[256];
		private int[] _nodes = new int[256];
		private int _count;
		public double PoppedCost;
		public bool IsEmpty => _count == 0;

		public void Clear() => _count = 0;

		public void Push(double cost, int node)
		{
			if (_count == _nodes.Length)
			{
				Array.Resize(ref _costs, _count * 2);
				Array.Resize(ref _nodes, _count * 2);
			}
			_costs[_count] = cost;
			_nodes[_count] = node;
			var index = _count;
			_count++;
			while (index > 0)
			{
				var parent = (index - 1) >> 1;
				if (_costs[parent] <= _costs[index]) break;
				Swap(parent, index);
				index = parent;
			}
		}

		public int Pop()
		{
			var topNode = _nodes[0];
			PoppedCost = _costs[0];
			var last = _count - 1;
			_costs[0] = _costs[last];
			_nodes[0] = _nodes[last];
			_count = last;
			var index = 0;
			while (true)
			{
				var left = index * 2 + 1;
				var right = left + 1;
				var smallest = index;
				if (left < last && _costs[left] < _costs[smallest]) smallest = left;
				if (right < last && _costs[right] < _costs[smallest]) smallest = right;
				if (smallest == index) break;
				Swap(smallest, index);
				index = smallest;
			}
			return topNode;
		}

		private void Swap(int a, int b)
		{
			(_costs[a], _costs[b]) = (_costs[b], _costs[a]);
			(_nodes[a], _nodes[b]) = (_nodes[b], _nodes[a]);
		}
	}
}
