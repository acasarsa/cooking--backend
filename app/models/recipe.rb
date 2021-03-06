require "json"
require "net/http"
require "open-uri"
require 'rest-client'

class Recipe < ApplicationRecord
    include Rails.application.routes.url_helpers
    has_many :likes
    has_many :comments
    has_many :recipe_tags
    has_many :recipe_ingredients
    has_many :tags, through: :recipe_tags
    has_many :ingredients, through: :recipe_ingredients
    belongs_to :user

    has_one_attached :imageFile

    def self.find_user_recipes(user_name)
        user = User.find_by(name: user_name)
        Recipe.all.select do |recipe|
            recipe.user_id == user.id
        end
    end

    def self.user_liked_recipes(user_id)
        user = User.find(user_id)
        likes_arr = user.likes
        liked_recipes = []
        like_obj = {}
        user.likes.each do |like_instance|
            recipe = Recipe.find(like_instance.recipe_id)
            recipe.image = recipe.getImageUrl
            like_obj = {:recipe => recipe}
            user = User.find(recipe.user_id)
            like_obj.merge!({:user => user})
            like_obj.merge!({:likes => recipe.likes})
            liked_recipes.push(like_obj)
        end
        liked_recipes
    end

    def self.find_following_recipes(user_name)
        user = User.find_by(name: user_name)
        following_ids = user.followings.map do |following|
            following.id 
        end
        recipes = []
        following_ids.each do |id|
            Recipe.all.each do |recipe|
                if recipe.user_id == id 
                    recipe.image = recipe.getImageUrl
                    recipes << recipe
                end
            end
        end
        recipes
    end
    
    def self.tag_recipes(tag_id)
        tag = Tag.find(tag_id)
        tag.recipes.map do |recipe|
            recipe.image = recipe.getImageUrl
            recipe
        end
    end

    def full_recipe_info(recipe_id)
        recipe={}
        # get whichever it is...
        self.image = getImageUrl
        recipe = {:recipe => self}        
        recipe.merge!({:user => self.user})
        # recipe.merge!({:ingredients => self.ingredients})
        recipe.merge!({:likes => self.likes})
        # recipe.merge!({:comments => self.comments})
        recipe.merge!({:comments => self.comment_info})
        recipe.merge!({:tags => self.tags})
        recipe.merge!({:ingredients => self.measurements})
    end

    def measurements
        self.recipe_ingredients.map do |ri|
            {id: ri.ingredient.id, name: ri.ingredient.name, quantity_number: ri.quantity_number, measurement: ri.measurement, instruction: ri.instruction}
        end
    end

    def comment_info 
        self.comments.map do |comment|
            {user: User.find(comment.user_id), comment: comment}
        end
    end

    def self.search_recipes(query)
        Recipe.all.select do |recipe|
            recipe.image = recipe.getImageUrl
            recipe.title.downcase.include?(query.downcase)
        end
    end

    def self.api_search(query)
        api_key = ENV['API_KEY']
        recipes_url = "https://api.spoonacular.com/recipes/search?apiKey=#{api_key}&query=#{query}"
        resp = RestClient.get(recipes_url)
        resp_json = JSON.parse(resp)
        # puts('API search:')
        # puts(resp_json)

        api_user = User.find_by(name: 'Spoonacular')

        resp_json['results'].map do |recipe_obj|
            Recipe.convert(recipe_obj, api_user)
        end
    end

    #create a Recipe object based on a given API search result
    #result is an array of objects, iterate over it, and create recipe for each element
    def self.convert(recipe_obj, api_user)
        recipe_title = recipe_obj['title']
        image_url = "https://spoonacular.com/recipeImages/#{recipe_title.parameterize}-#{recipe_obj['id']}.jpg"
        Recipe.new(title: recipe_title, user: api_user, image: image_url, isPublic: true, api_id: recipe_obj['id'])
    end

    #when user click 'details', grab result from api call, and assign user Spoonacular to this recipe
    def self.get_recipe_from_api(recipe_api_id)
        api_user = User.find_by(name: 'Spoonacular')
        api_key = ENV['API_KEY']
        curr_recipe_url = "https://api.spoonacular.com/recipes/#{recipe_api_id}/information?apiKey=#{api_key}"
        curr_recipe = RestClient.get(curr_recipe_url)
        curr_recipe_json = JSON.parse(curr_recipe)

        recipe_title = curr_recipe_json['title']
        image_url = "https://spoonacular.com/recipeImages/#{recipe_title.parameterize}-#{recipe_api_id}.jpg"

        new_recipe = Recipe.create(title: recipe_title, 
            image: image_url, 
            description: curr_recipe_json['summary'],
            steps: curr_recipe_json['instructions'],
            user: api_user,
            isPublic: true,
            api_id: recipe_api_id
        )
        Recipe.relation_recipe(recipe_title, curr_recipe_json)
        return new_recipe
    end


    #add steps, descriptions to recipe, also create recipe_ingredient and recipe_tag
    def self.relation_recipe(title, api_response)
        recipe = Recipe.find_by(title: title)

        ingredients_arr = api_response['extendedIngredients']

        ingredients_arr.each do |ingredient|
            ing = Ingredient.find_by(name: ingredient['name'])
            if ing #if ingredient exist, create join table for with this recipe and existing ingredient
                RecipeIngredient.create(recipe: recipe, ingredient: ing, quantity_number: ingredient['measures']['us']['amount'].to_f, measurement: ingredient['measures']['us']['unitLong'], instruction: ingredient['originalString'])
            else #if ingredinet is new, create new ingredient first, then relate new ingredient and this recipe
                new_ing = Ingredient.create(name: ingredient['name'])
                RecipeIngredient.create(recipe: recipe, ingredient: new_ing, quantity_number: ingredient['measures']['us']['amount'].to_f, measurement: ingredient['measures']['us']['unitLong'], instruction: ingredient['originalString'])
            end
        end

        #possible tags that the api response gives
        tags_arr = (api_response['cuisines'] + api_response['dishTypes']).uniq
        puts "API CUISINE AND DISH TYPE"
        puts "API CUISINE AND DISH TYPE"
        puts "API CUISINE AND DISH TYPE"
        puts "API CUISINE AND DISH TYPE"
        puts "API CUISINE AND DISH TYPE"
        puts tags_arr
        tags_arr.each do |t|
            tag = Tag.find_by(name: t)
            if tag #if tag is already exist, relate recipe and tag
                RecipeTag.create(recipe: recipe, tag: tag)
            else
                new_tag = Tag.create(name: t)
                RecipeTag.create(recipe: recipe, tag: new_tag)
            end
        end
    end

    def set_tags(tags)
        self.tags = []
        tags.each do |tag_param|
            puts "TAG PARAM"
            puts "TAG PARAM"
            puts "TAG PARAM"
            puts tag_param
            puts tag_param["name"]
            tag = Tag.find_or_create_by(name: tag_param["name"])
            puts tag
            self.tags << tag
        end
    end

    def set_ingredients(ingredients)
        self.ingredients = []
        ingredients.each do |ing_param|
            puts "INGREDIENT PARAM"
            puts "INGREDIENT PARAM"
            puts "INGREDIENT PARAM"
            puts ing_param
            puts ing_param["name"]
            ing = Ingredient.find_or_create_by(name: ing_param["name"])
            ri = RecipeIngredient.new(recipe: self, ingredient: ing)
            # set the other metadata
            ri.quantity_number = ing_param["quantity_number"]
            ri.measurement = ing_param["measurement"]
            ri.instruction = ing_param["instruction"]
            ri.save
        end
    end

    #
    #
    #
    #
    #
    #
    # IMAGE BASED INTERCTION
    #
    #
    #
    #
    #
    #

    def updateImage(params)
        if params[:changedImage] && params[:changedImage] == "true" then
            puts "IMAGE CHANGED CHANGED CHANGED CHANGED CHANGED CHANGED"
            puts params

            # automatically purge the file if we've changed
            delete_image if self.imageFile.attached?

            if params[:imageSrc] && file?(params[:imageSrc]) then
                self.imageFile = params[:imageSrc]
                self.image = nil
                # do we need to save, too?
                # self.save
            elsif params[:imageURL] && params[:imageURL] != "null" && params[:imageURL] != "undefined" then
                self.image = params[:imageURL]
                puts params[:imageURL]
                # self.save
            else
                puts "no image anymore"
                self.image = nil
            end
        else
            puts "IMAGE NOT CHANGED"
            puts "IMAGE NOT CHANGED"
            puts "IMAGE NOT CHANGED"
            puts params
        end
    end

    def getImageUrl
        if self.image then
            return self.image
        elsif self.imageFile.attached? then 
            # return self.imageFile.blob.attributes
            #         .slice('filename', 'byte_size')
            #         .merge(url: image_url_from_file)
            #         .tap { |attrs| attrs['name'] = attrs.delete('filename') }
            return image_url_from_file
        end
    end

    def image_url_from_file
        url_for(self.imageFile)
    end

    def file?(param)
        param.is_a?(ActionDispatch::Http::UploadedFile)
    end

    def delete_image
        self.imageFile.purge
    end

    def create_copy(current_user)
        # need to copy the recipe as well as 
        # change the user
        # copy all of the references
        # tags
        # ingredients
        # but not the likes
        #
        # how do we copy the image?
        copy = self.dup
        copy.user = current_user

        #tags
        self.tags.each do |tag|
            copy.tags << tag
        end



        #ingredients
        self.recipe_ingredients.each do |ri|
            copy.recipe_ingredients << ri
        end

            

        #image?
        if self.imageFile.attached? then
            copy.imageFile.attach(self.imageFile.blob)
        end



        puts "COPY COPY COPY"
        puts copy

        if copy.save then
            return copy.id
        else
            return nil
        end
    end
end
