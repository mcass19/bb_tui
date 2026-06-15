defmodule BB.TUI.Viz.RobotScene do
  @moduledoc """
  Builds an `ExRatatui.ThreeD.Scene` from a `BB.Robot` topology and live joint
  positions, running forward kinematics.

  The robot is Z-up (URDF); the whole tree is wrapped in a -90°-about-X root frame
  so it renders in the engine's Y-up conventions. Pure: `(robot_struct, positions)`
  in, `Scene` out.
  """

  require Logger

  alias ExRatatui.ThreeD.{Camera, Light, Material, Mesh, Node, Object, Scene, Transform}

  @default_color {160, 160, 170}
  @half_pi :math.pi() / 2.0

  @doc """
  Builds the 3D scene for `robot` at the given joint `positions`.

  Options: `:lights` and `:background` override the defaults.
  """
  @spec build(struct(), %{atom() => number()}, keyword()) :: Scene.t()
  def build(robot, positions, opts \\ []) do
    root_node = %Node{
      transform: %Transform{rotation: {:axis_angle, {1.0, 0.0, 0.0}, -@half_pi}},
      children: [link_node(robot, robot.root_link, positions)]
    }

    Node.to_scene(root_node,
      lights: Keyword.get(opts, :lights, default_lights()),
      background: Keyword.get(opts, :background, {16, 16, 22})
    )
  end

  @doc "A sensible default orbit camera for the arm."
  @spec default_camera() :: Camera.t()
  def default_camera do
    %Camera{position: {0.4, 0.35, 0.4}, target: {0.0, 0.12, 0.0}}
  end

  defp default_lights do
    [
      Light.ambient({110, 110, 120}, 1.0),
      Light.directional({1.0, 1.0, 1.0}, {255, 255, 255}, intensity: 1.0),
      Light.directional({-1.0, 1.0, -1.0}, {255, 255, 255}, intensity: 0.5)
    ]
  end

  # A link node: identity frame, optional visual, children = child joint nodes.
  defp link_node(robot, link_name, positions) do
    link = Map.fetch!(robot.links, link_name)

    %Node{
      transform: %Transform{},
      visual: visual_object(link.visual),
      children: Enum.map(link.child_joints, &joint_node(robot, &1, positions))
    }
  end

  # A joint node: frame = origin ∘ motion, child = the joint's child link.
  defp joint_node(robot, joint_name, positions) do
    joint = Map.fetch!(robot.joints, joint_name)
    value = Map.get(positions, joint_name, 0.0)

    %Node{
      transform: joint_frame(joint, value),
      children: [link_node(robot, joint.child_link, positions)]
    }
  end

  defp joint_frame(joint, value) do
    origin = origin_transform(joint.origin)
    Transform.compose(origin, motion(joint.type, joint.axis, value))
  end

  defp motion(type, axis, value) when type in [:revolute, :continuous] do
    %Transform{rotation: {:axis_angle, axis_or_z(axis), value}}
  end

  defp motion(:prismatic, axis, value) do
    {ax, ay, az} = axis_or_z(axis)
    %Transform{position: {ax * value, ay * value, az * value}}
  end

  defp motion(_type, _axis, _value), do: %Transform{}

  defp axis_or_z(nil), do: {0.0, 0.0, 1.0}
  defp axis_or_z({_, _, _} = axis), do: axis

  # Joint origin: %{position:, orientation:}. Build translate ∘ rpy.
  defp origin_transform(nil), do: %Transform{}

  defp origin_transform(%{position: pos, orientation: rpy}) do
    Transform.compose(%Transform{position: pos}, rpy_transform(rpy))
  end

  # URDF rpy = Rz(yaw)·Ry(pitch)·Rx(roll).
  defp rpy_transform({roll, pitch, yaw}) do
    rx = %Transform{rotation: {:axis_angle, {1.0, 0.0, 0.0}, roll}}
    ry = %Transform{rotation: {:axis_angle, {0.0, 1.0, 0.0}, pitch}}
    rz = %Transform{rotation: {:axis_angle, {0.0, 0.0, 1.0}, yaw}}
    Transform.compose(Transform.compose(rz, ry), rx)
  end

  defp visual_object(nil), do: nil

  defp visual_object(%{geometry: geometry} = visual) do
    {mesh, geom_transform} = geometry_mesh(geometry)
    origin = visual_origin_transform(Map.get(visual, :origin))

    %Object{
      mesh: mesh,
      material: %Material{color: color(Map.get(visual, :material))},
      transform: Transform.compose(origin, geom_transform)
    }
  end

  # Link visual origin is a 2-tuple {position, orientation} (or nil).
  defp visual_origin_transform(nil), do: %Transform{}

  defp visual_origin_transform({pos, rpy}) do
    Transform.compose(%Transform{position: pos}, rpy_transform(rpy))
  end

  # geometry -> {mesh, transform applying scale (+ axis fix for cylinder)}
  defp geometry_mesh({:box, %{x: x, y: y, z: z}}) do
    {Mesh.cube(), %Transform{scale: {x, y, z}}}
  end

  defp geometry_mesh({:sphere, %{radius: r}}) do
    {Mesh.sphere(), %Transform{scale: {2.0 * r, 2.0 * r, 2.0 * r}}}
  end

  defp geometry_mesh({:cylinder, %{radius: r, height: h}}) do
    # Primitive axis +Y; URDF axis +Z. Scale in primitive frame then +90° about X.
    {Mesh.cylinder(),
     %Transform{rotation: {:axis_angle, {1.0, 0.0, 0.0}, @half_pi}, scale: {2.0 * r, h, 2.0 * r}}}
  end

  defp geometry_mesh(other) do
    Logger.warning("RobotScene: unsupported geometry #{inspect(other)}; using a unit cube")
    {Mesh.cube(), %Transform{}}
  end

  defp color(%{color: %{red: r, green: g, blue: b}}), do: {ch(r), ch(g), ch(b)}
  defp color(_), do: @default_color

  defp ch(v), do: v |> Kernel.*(255) |> round() |> max(0) |> min(255)
end
