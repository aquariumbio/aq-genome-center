# A series of common methods that are shared between many of the surveillance protocols.
# Cannon Mallory
# malloc3@uw.edu

needs 'Container/ItemContainer'
needs 'Container/KitHelper'
needs 'CompositionLibs/AbstractComposition'
needs 'CompositionLibs/CompositionHelper'


module CovidSurveillanceHelper
  include KitHelper
  include CompositionHelper

  # coordinates finding and setting up a kit with the composition libs
  #
  # @param kit_sample_name [String] the sample name of the kit
  # @param num_reactions_required [Int] the number of reactions that are required
  # @param composition [Composition] the composition that is being used
  # @return Kit [KitComponent] the kit that was found
  def setup_kit_composition(kit_sample_name:,
                            num_reactions_required:,
                            components:,
                            consumables:)
    kit = find_kit(kit_sample_name, num_reactions_required)

    composition = CompositionFactory.build(
      components: components.append(kit.components).flatten,
      consumables: consumables.append(kit.consumables).flatten,
    )
    set_kit_item(kit, composition)
    [composition, kit]
  end

  # Rejects all things in the list
  #
  # @param list_of_rejections [Array<string>] string = sample name
  # @param components [Array<Component>]
  # @return [Array<Components>]
  def reject_components(list_of_rejections:, components:)
    return_components = components.clone
    list_of_rejections.each do |input_name|
      return_components.reject!{ |comp| comp.input_name == input_name }
    end
    return_components
  end

  def master_mix_handler(components:, mm:, adjustment_multiplier:, mm_container:)
    mm.item = make_item(sample: mm.sample,
                        object_type: mm.object_type)
    show_block = label_items(
      objects: [mm_container],
      labels: [mm.item]
    )
    adjust_volume(components: components,
                  multi: adjustment_multiplier)
    show_block += create_master_mix(
      components: components,
      master_mix: mm,
      adj_qty: true
    )
    show_block
  end

  def use_robot(program:, robot:, items:)
    show_block = []
    show_block.append(robot.select_program_template(program: program))
    items.each do |item|
      show_block.append(robot.place_item(item: item))
    end
    show_block.append(robot.follow_template_instructions)
    show_block.append(wait_for_instrument(instrument_name: robot.model_and_name))
  end


  # Instructions to place plate on some magnets
  #
  # @param plate [Item]
  def place_on_magnet(plate)
    show_block = []
    show_block.append("Put plate #{plate} on magnetic stand and wait until clear (~3 Min)")
  end

  # Instructions to remove plate from magnet
  #
  # @param plate [Collection]
  def remove_from_magnet(plate)
    show_block = []
    show_block.append("Remove plate #{plate} from magnetic stan")
  end

  # Instruction to pipet up and down to mix
  #
  # @param plate [Collection]
  def pipet_up_and_down(plate)
    show_block = []
    show_block.append('Set Pipet to 35 ul')
    show_block.append("Pipet up and down to mix all wells of plate #{plate}")
  end

end
