# A series of common methods that are shared between many of the surveillance protocols.
# Cannon Mallory
# malloc3@uw.edu

needs 'Container/ItemContainer'
needs 'Container/KitHelper'
needs 'Composition Libs/Composition'
needs 'Composition Libs/CompositionHelper'
needs 'Standard Libs/TextDisplayHelper'

module CovidSurveillanceHelper
  include KitHelper
  include CompositionHelper
  include TextDisplayHelper

  # coordinates finding and setting up a kit with the composition libs
  #
  # @param kit_sample_name [String] the sample name of the kit
  # @param num_reactions_required [Int] the number of reactions that are required
  # @param composition [Composition] the composition that is being used
  # @return Kit [KitComponent] the kit that was found
  def setup_kit_composition(kit_sample_names:,
                            num_reactions_required:,
                            components:,
                            consumables:)
    all_comps = components
    all_cons = consumables
    kits = []
    kit_sample_names.each do |kit_name|
      kit = find_kit(kit_name, num_reactions_required)
      all_comps += kit.components
      all_cons +=  kit.consumables
      kits.push(find_kit(kit_name, num_reactions_required))
    end

    composition = CompositionFactory.build(
      component_data: all_comps
    )

    kits.each do |kit|
      set_kit_item(kit, composition)
    end

    [composition,
     ConsumablesFactory.build(
       consumable_data: all_cons
     ),
     kits]
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

  def master_mix_handler(components:, mm:, mm_container:, adjustment_multiplier: nil)
    mm.item = make_item(sample: mm.sample,
                        object_type: mm.suggested_ot)
    show_block = label_items(
      objects: [mm.item.object_type.name],
      labels: [mm.display_name]
    )

    if adjustment_multiplier
      adjust_volume(components: components,
                    multi: adjustment_multiplier)
    end

    show_block += create_master_mix(
      components: components,
      master_mix: mm,
      adj_qty: true
    )
    show_block
  end

  def use_robot(program:, robot:, items:)
    show_block = []

    show_block.append(
      { display: robot.move_to_robot,
        type: 'note' }
    )

    show_block.append(
      { display: robot.select_program_template(program: program),
        type: 'note' }
    )

    items.each do |item|
      show_block.append(
        { display: robot.place_item(item: item),
          type: 'note' }
      )
    end

    # SOmething about order of plates

    show_block.append(
      { display: robot.follow_template_instructions,
        type: 'note' }
    )

    show_block.append(
      { display: robot.start_run,
        type: 'note'}
    )
    show_block.append(
      { display: wait_for_instrument(instrument_name: robot.model_and_name),
        type: 'note' }
    )

    show_block
  end

  # Creates show block following instructions for show block
  #
  # @param title 'String' the string of things to show
  # @param has_to_show: 'Array<Hash>' hash to represent each line
  def display_hash(title:, hash_to_show:)
    display(title: title, show_block: hash_to_show)
  end

  # Instructions to place plate on some magnets
  #
  # @param plate [Item]
  def place_on_magnet(plate, time_min: 3)
    show_block = []
    show_block.append("Put plate #{plate} on magnetic stand and wait until"\
                      " clear (~#{time_min} Min)")
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
    plate = [plate] unless plate.is_a? Array
    show_block = []
    show_block.append('Set Pipet to 35 ul')
    show_block.append('Pipet up and down to mix the following:')
    plate.each do |p|
      show_block.append(p.to_s)
    end
  end

end
